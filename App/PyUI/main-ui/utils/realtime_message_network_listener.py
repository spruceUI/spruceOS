import socket
import threading
import sys
from display.display import Display
from option_select_ui import OptionSelectUI
from utils.logger import PyUiLogger

class RealtimeMessageNetworkListener:
    def __init__(self, port: int):
        self.host = "0.0.0.0"
        self.port = int(port)
        self.server_socket = None
        self.stop_event = threading.Event()
        self.logger = PyUiLogger.get_logger()
        self.threads = []

    def start(self):
        """Start the message listener server."""
        self.logger.info(f"Starting RealtimeMessageNetworkListener on port {self.port}...")

        # Setup socket
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.logger.info(f"Listening for connections on {self.host}:{self.port}")

        try:
            while not self.stop_event.is_set():
                self.server_socket.settimeout(1.0)
                try:
                    conn, addr = self.server_socket.accept()
                    thread = threading.Thread(
                        target=self._handle_client, args=(conn, addr), daemon=True
                    )
                    thread.start()
                    self.threads.append(thread)
                except socket.timeout:
                    continue
        except KeyboardInterrupt:
            self.logger.info("Keyboard interrupt received, shutting down...")
        finally:
            self.stop()

    def _handle_client(self, conn, addr):
        """Handle messages from a single client."""
        self.logger.info(f"Client connected from {addr}")
        try:
            with conn:
                buf = b""
                while not self.stop_event.is_set():
                    data = conn.recv(1024)
                    if not data:
                        break
                    buf += data
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        message = line.decode("utf-8", errors="ignore").strip()
                        self._process_message(message)
                        if self.stop_event.is_set():
                            break
        except Exception:
            self.logger.error(f"Error handling client {addr}", exc_info=True)
        finally:
            self.logger.info(f"Client {addr} disconnected")

    def _process_message(self, message: str):
        """Process a single incoming message."""
        self.logger.info(f"Received Message: {message}")

        if message == "EXIT_APP":
            self.logger.info("Received EXIT_APP command, shutting down...")
            self.stop_event.set()
            return

        if message.startswith("RENDER_IMAGE:"):
            image_path = message[len("RENDER_IMAGE:"):].strip()
            self.logger.info(f"Rendering image from path: {image_path}")
            Display.display_image(image_path)
        elif message.startswith("OPTION_LIST:"):
            option_list_file = message[len("OPTION_LIST:"):].strip()
            PyUiLogger.get_logger().info(f"Option list file: {option_list_file}")
            OptionSelectUI.display_option_list("",option_list_file, False)
        else:
            Display.display_message(message)

    def stop(self):
        """Gracefully stop the server and all threads."""
        self.stop_event.set()
        if self.server_socket:
            try:
                self.server_socket.close()
            except Exception:
                pass
        self.logger.info("RealtimeMessageNetworkListener shutting down")

        for t in self.threads:
            if t.is_alive():
                t.join(timeout=1)

        sys.exit(0)
