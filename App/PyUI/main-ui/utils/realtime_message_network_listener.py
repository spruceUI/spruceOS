import socket
import threading
import sys
import queue
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
        self.message_queue = queue.Queue()  # thread-safe message handoff

    def start(self):
        """Start the message listener server (runs on main thread)."""
        self.logger.info(f"Starting RealtimeMessageNetworkListener on port {self.port}...")

        # Setup socket
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.logger.info(f"Listening for connections on {self.host}:{self.port}")
        #Display.display_message(f"Listening for connections on {self.host}:{self.port}")

        try:
            while not self.stop_event.is_set():
                self.server_socket.settimeout(0.2)

                # ---- Process any queued messages safely on the main thread ----
                self._process_queued_messages()

                # ---- Accept new clients (with timeout so we can poll the queue) ----
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
        """Handle messages from a single client (runs in background thread)."""
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
                        self._enqueue_message(message)
                        if self.stop_event.is_set():
                            break
        except Exception:
            self.logger.error(f"Error handling client {addr}", exc_info=True)
        finally:
            self.logger.info(f"Client {addr} disconnected")

    def _enqueue_message(self, message: str):
        """Push a message into the main-thread queue."""
        self.logger.info(f"Received Message: {message}")
        self.message_queue.put(message)

    def _process_queued_messages(self):
        """Run on main thread: drain and handle queued messages."""
        try:
            while True:
                message = self.message_queue.get_nowait()
                self._handle_ui_message(message)
        except queue.Empty:
            pass

    def _handle_ui_message(self, message: str):
        """Perform SDL/UI operations safely (main thread only)."""
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
            self.logger.info(f"Option list file: {option_list_file}")
            OptionSelectUI.display_option_list("", option_list_file, False)
        else:
            self.logger.info(f"Displaying message: {message}")
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
