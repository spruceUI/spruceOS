
from abc import ABC, abstractmethod

from games.utils.game_system import GameSystem


class GameSystemUtils(ABC):
    
    @abstractmethod
    def get_game_system_by_name(self, system_name) -> GameSystem:
        pass

    @abstractmethod
    def get_active_systems(self):
        pass

