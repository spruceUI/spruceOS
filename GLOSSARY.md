# spruceOS PyUI

Giao diện menu PyUI trên máy chơi game cầm tay (OTA update, updater, theme theo máy).

## Language

**Ô fill**:
Ô vuông đã tải trong thanh tiến trình, màu nhấn của theme.
_Avoid_: ô sáng, ô đặc, ô trắng

**Ô track**:
Ô vuông chưa tải trong thanh tiến trình, cùng hue với ô fill nhưng pha tối để luôn phân biệt được.
_Avoid_: ô nền, ô mờ, ô xám

**font fallback**:
Cơ chế vẽ ký tự mà font theme thiếu bằng font dự phòng cùng cỡ, để không còn ô vuông.
_Avoid_: font thay thế, font dự phòng sai cỡ

**tofu**:
Ô vuông □ hiện thay cho ký tự khi font đang dùng thiếu glyph đó.
_Avoid_: ô lỗi, ký tự rác

**run**:
Đoạn ký tự liên tiếp trong một chuỗi được vẽ bằng cùng một font (primary hoặc fallback).
_Avoid_: đoạn chữ, chunk
