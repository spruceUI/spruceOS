from dataclasses import dataclass


@dataclass
class WiFiConnectionQualityInfo:
    noise_level: int
    signal_level: int
    link_quality: int