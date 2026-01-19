import socket
import threading
import sys
import queue
import json
from pathlib import Path
from devices.device import Device
from display.display import Display
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from menus.common.top_bar import TopBar
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

    def _write_to_file(self,result):
        """Write selection result to selection.txt next to package root (two levels up)."""
        script_dir = Path(__file__).resolve().parent.parent.parent
        result_file = script_dir / "realtime_message_network_listener.txt"
        PyUiLogger.get_logger().info(f"Writing {result} to {result_file}")
        try:
            with result_file.open("w", encoding="utf-8") as f:
                f.write(result)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Error writing result to file: {e}")

    def start(self):
        """Start the message listener server (runs on main thread)."""
        self.logger.info(f"Starting RealtimeMessageNetworkListener on port {self.port}...")

        # Setup socket
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.logger.info(f"Listening for connections on {self.host}:{self.port}")
        self._write_to_file("Listening on port " + str(self.port))
        try:
            while not self.stop_event.is_set():
                self.server_socket.settimeout(0.2)

                # Process any queued messages safely on the main thread
                self._process_queued_messages()

                # Accept new clients (with timeout so we can poll the queue)
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
                        raw_message = line.decode("utf-8", errors="ignore").strip()
                        self._enqueue_message(raw_message)

                        if self.stop_event.is_set():
                            break

        except Exception:
            self.logger.error(f"Error handling client {addr}", exc_info=True)
        finally:
            self.logger.info(f"Client {addr} disconnected")

    def _enqueue_message(self, raw_message: str):
        """Push a message into the main-thread queue (raw JSON string)."""
        self.logger.info(f"Received Raw Message: {raw_message}")
        self.message_queue.put(raw_message)

    def _process_queued_messages(self):
        """Main thread: drain and process queued messages."""
        try:
            while True:
                raw_message = self.message_queue.get_nowait()
                self._handle_ui_message(raw_message)
        except queue.Empty:
            pass

    def _progress_bar(self, percent):
        """
        Returns an ASCII progress bar rounded to nearest 5%.
        Example: progress_bar(34) → "[███████···········] 35%"
        """
        # Round to nearest 5%
        rounded = round(percent / 5) * 5

        # Total bar resolution: 20 segments (20 × 5% = 100%)
        total_segments = 20
        filled = rounded // 5  # each block is 5%

        bar = "█" * filled + "·" * (total_segments - filled)
        return f"[{bar}] {percent}%"

    def _handle_ui_message(self, raw_message: str):
        """
        Handle a JSON-formatted UI command.
        """
        # ---------------------------
        # Parse JSON
        # ---------------------------
        try:
            data = json.loads(raw_message)
            cmd = str(data.get("cmd", "")).upper()
            args = data.get("args", [])
            if not isinstance(args, list):
                args = [args]

            self.logger.info(f"Parsed cmd={cmd}, args={args}")

        except Exception:
            self.logger.error(f"Invalid JSON received: {raw_message}", exc_info=True)
            Display.display_message(raw_message)
            return

        try:
            # ---------------------------
            # Handle Commands
            # ---------------------------
            if cmd == "EXIT_APP":
                self.logger.info("Received EXIT_APP command, shutting down...")
                self.stop_event.set()
                return

            elif cmd == "RENDER_IMAGE":
                if args:
                    image_path = args[0]
                    self.logger.info(f"Rendering image from path: {image_path}")
                    Display.display_image(image_path)
                else:
                    self.logger.error("RENDER_IMAGE missing args")

            elif cmd == "IMAGE_AND_TEXT":
                if args:
                    padding = Display.get_top_bar_height()

                    image_path = args[0]
                    text = args[1]
                    height_percent = int(args[2])  
                    
                    # Use usable height (excluding top bar)
                    usable_height = Display.get_usable_screen_height()

                    # Image metrics
                    image_height = int(usable_height * (height_percent / 100))

                    image_y = int(int(args[3])/100 * usable_height) + padding
                    text_y = int(int(args[4])/100 * usable_height) + padding


                    self.logger.info(f"Rendering image from path: {image_path} with text: {text}")

                    Display.clear("")

                    Display.render_image(
                        image_path,
                        Device.get_device().screen_width() // 2,
                        image_y,
                        RenderMode.TOP_CENTER_ALIGNED,
                        Device.get_device().screen_width(),
                        image_height
                    )

                    Display.write_message_multiline_starting_height_specified(
                        Display.split_message(text, FontPurpose.LIST, clip_to_device_width=True),
                        text_y
                    )

                    Display.present()
                else:
                    self.logger.error("TOP_IMAGE_BOTTOM_TEXT missing args")
            elif cmd == "TEXT_WITH_PERCENTAGE_BAR":
                if args:
                    text = args[0]
                    args[1] = int(args[1]) 
                    percentage = args[1]
                    self.logger.info(f"Rendering text: {text} w/ perc(entage bar: {percentage}%")
                    Display.clear("")
                    Display.write_message_multiline(Display.split_message(text, FontPurpose.LIST,clip_to_device_width=True), Device.get_device().screen_height()*0.35)
                    Display.write_message_multiline([self._progress_bar(percentage)], (Device.get_device().screen_height()*0.6))                    
                    if(len(args) > 2):
                        Display.write_message_multiline(Display.split_message(args[2], FontPurpose.LIST,clip_to_device_width=True), Device.get_device().screen_height()*0.7)
                    Display.present()
                else:
                    self.logger.error("TEXT_WITH_PERCENTAGE_BAR missing args")

            elif cmd == "OPTION_LIST":
                if args:
                    file_path = args[0]
                    self.logger.info(f"Option list file: {file_path}")
                    OptionSelectUI.display_option_list("", file_path, False)
                else:
                    self.logger.error("OPTION_LIST missing args")
            elif cmd == "MESSAGE":
                if args:
                    msg = " ".join(str(a) for a in args)
                    self.logger.info(f"Displaying message: {msg}")
                    Display.display_message(msg)
                else:
                    self.logger.error("MESSAGE missing args")

            else:
                # Default handler for unknown commands
                msg = " ".join(str(a) for a in args) if args else cmd
                self.logger.info(f"Displaying message: {msg}")
                Display.display_message(msg)
        except Exception:
            self.logger.error(f"Error processing command: {cmd} with args: {args}", exc_info=True)

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
