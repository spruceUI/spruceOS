from .ansi import Fore, Back, Style, ExtendedStyle


style = {
    'b':  Style.BRIGHT,
    'd':  Style.DIM,
    'n':  Style.NORMAL,
    '0':  Style.RESET_ALL,
    'h':  ExtendedStyle.HIDE,
    'i':  ExtendedStyle.ITALIC,
    'l':  ExtendedStyle.BLINK,
    's':  ExtendedStyle.STRIKE,
    'u':  ExtendedStyle.UNDERLINE,
    'v':  ExtendedStyle.REVERSE,

    'bold':       Style.BRIGHT,
    'dim':        Style.DIM,
    'normal':     Style.NORMAL,
    'reset':      Style.RESET_ALL,
    'hide':       ExtendedStyle.HIDE,
    'italic':     ExtendedStyle.ITALIC,
    'blink':      ExtendedStyle.BLINK,
    'strike':     ExtendedStyle.STRIKE,
    'underline':  ExtendedStyle.UNDERLINE,
    'reverse':    ExtendedStyle.REVERSE,
}

foreground = {
    'k':  Fore.BLACK,
    'r':  Fore.RED,
    'g':  Fore.GREEN,
    'y':  Fore.YELLOW,
    'e':  Fore.BLUE,
    'm':  Fore.MAGENTA,
    'c':  Fore.CYAN,
    'w':  Fore.WHITE,

    'lk':  Fore.LIGHTBLACK_EX,
    'lr':  Fore.LIGHTRED_EX,
    'lg':  Fore.LIGHTGREEN_EX,
    'ly':  Fore.LIGHTYELLOW_EX,
    'le':  Fore.LIGHTBLUE_EX,
    'lm':  Fore.LIGHTMAGENTA_EX,
    'lc':  Fore.LIGHTCYAN_EX,
    'lw':  Fore.LIGHTWHITE_EX,

    'black':    Fore.BLACK,
    'red':      Fore.RED,
    'green':    Fore.GREEN,
    'yellow':   Fore.YELLOW,
    'blue':     Fore.BLUE,
    'magenta':  Fore.MAGENTA,
    'cyan':     Fore.CYAN,
    'white':    Fore.WHITE,

    'light-black':    Fore.LIGHTBLACK_EX,
    'light-red':      Fore.LIGHTRED_EX,
    'light-green':    Fore.LIGHTGREEN_EX,
    'light-yellow':   Fore.LIGHTYELLOW_EX,
    'light-blue':     Fore.LIGHTBLUE_EX,
    'light-magenta':  Fore.LIGHTMAGENTA_EX,
    'light-cyan':     Fore.LIGHTCYAN_EX,
    'light-white':    Fore.LIGHTWHITE_EX,
}

background = {
    'K':  Back.BLACK,
    'R':  Back.RED,
    'G':  Back.GREEN,
    'Y':  Back.YELLOW,
    'E':  Back.BLUE,
    'M':  Back.MAGENTA,
    'C':  Back.CYAN,
    'W':  Back.WHITE,

    'LK':  Back.LIGHTBLACK_EX,
    'LR':  Back.LIGHTRED_EX,
    'LG':  Back.LIGHTGREEN_EX,
    'LY':  Back.LIGHTYELLOW_EX,
    'LE':  Back.LIGHTBLUE_EX,
    'LM':  Back.LIGHTMAGENTA_EX,
    'LC':  Back.LIGHTCYAN_EX,
    'LW':  Back.LIGHTWHITE_EX,

    'BLACK':    Back.BLACK,
    'RED':      Back.RED,
    'GREEN':    Back.GREEN,
    'YELLOW':   Back.YELLOW,
    'BLUE':     Back.BLUE,
    'MAGENTA':  Back.MAGENTA,
    'CYAN':     Back.CYAN,
    'WHITE':    Back.WHITE,

    'LIGHT-BLACK':    Back.LIGHTBLACK_EX,
    'LIGHT-RED':      Back.LIGHTRED_EX,
    'LIGHT-GREEN':    Back.LIGHTGREEN_EX,
    'LIGHT-YELLOW':   Back.LIGHTYELLOW_EX,
    'LIGHT-BLUE':     Back.LIGHTBLUE_EX,
    'LIGHT-MAGENTA':  Back.LIGHTMAGENTA_EX,
    'LIGHT-CYAN':     Back.LIGHTCYAN_EX,
    'LIGHT-WHITE':    Back.LIGHTWHITE_EX,
}

all_tags = {}
for i in style, foreground, background:
    all_tags.update(i)
