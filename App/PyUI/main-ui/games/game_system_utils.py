

from abc import ABC, abstractmethod
import threading

from games.utils.game_system import GameSystem


class GameSystemUtils(ABC):

    _prefetch_thread = None
    _prefetch_result = None

    def prefetch_active_systems(self):
        """Starts scanning the active systems in the background."""
        def scan():
            self._prefetch_result = self.get_active_systems()

        self._prefetch_thread = threading.Thread(target=scan, daemon=True)
        self._prefetch_thread.start()

    def take_prefetched_active_systems(self) -> list[GameSystem]:
        """Returns the active systems, taking the pending background scan if there is one."""
        thread, self._prefetch_thread = self._prefetch_thread, None
        if thread is None:
            return self.get_active_systems()
        thread.join()
        result, self._prefetch_result = self._prefetch_result, None
        return result if result is not None else self.get_active_systems()

    @abstractmethod
    def get_game_system_by_name(self, system_name) -> GameSystem:
        pass

    @abstractmethod
    def get_active_systems(self) -> list[GameSystem]:
        pass
