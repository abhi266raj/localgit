"""Terminal UI formatting and styling utilities for LocalGit."""

import sys


class Style:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    ITALIC = "\033[3m"
    UNDERLINE = "\033[4m"

    # Foreground
    BLACK = "\033[30m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"

    # Bright foreground
    BRIGHT_RED = "\033[91m"
    BRIGHT_GREEN = "\033[92m"
    BRIGHT_YELLOW = "\033[93m"
    BRIGHT_BLUE = "\033[94m"
    BRIGHT_MAGENTA = "\033[95m"
    BRIGHT_CYAN = "\033[96m"
    BRIGHT_WHITE = "\033[97m"


def print_banner():
    banner = f"""{Style.BRIGHT_CYAN}{Style.BOLD}
  _                     _  ____ _ _   
 | |    ___   ___ __ _| |/ ___(_) |_ 
 | |   / _ \\ / __/ _` | | |  _| | __|
 | |__| (_) | (_| (_| | | |_| | | |_ 
 |_____\\___/ \\___\\__,_|_|\\____|_|\\__|
{Style.RESET}{Style.DIM} Local Apple Foundation Model Git Agent (powered by `fm`){Style.RESET}
"""
    print(banner)


def info(msg: str):
    print(f"{Style.BRIGHT_BLUE}ℹ{Style.RESET} {msg}")


def success(msg: str):
    print(f"{Style.BRIGHT_GREEN}✔{Style.RESET} {Style.BOLD}{msg}{Style.RESET}")


def warning(msg: str):
    print(f"{Style.BRIGHT_YELLOW}▲{Style.RESET} {msg}")


def error(msg: str):
    print(f"{Style.BRIGHT_RED}✖{Style.RESET} {Style.BOLD}{msg}{Style.RESET}")


def model_msg(thought: str, command: str, explanation: str):
    if thought:
        print(f"{Style.DIM}🧠 Analysis: {thought}{Style.RESET}")
    print(f"{Style.BRIGHT_CYAN}🤖 Proposed Command:{Style.RESET} {Style.BOLD}{command}{Style.RESET}")
    if explanation:
        print(f"{Style.DIM}   Explanation: {explanation}{Style.RESET}")


def executing_msg(cmd: str):
    print(f"{Style.BRIGHT_MAGENTA}⚡ Executing (auto-run):{Style.RESET} {Style.BOLD}{cmd}{Style.RESET}")


def retry_msg(attempt: int, max_retries: int):
    print(f"{Style.BRIGHT_YELLOW}🔄 Error encountered. Asking Apple FM model to diagnose & fix (attempt {attempt}/{max_retries})...{Style.RESET}")
