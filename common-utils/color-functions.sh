# Define color codes
MAKE_IT_RED='\033[0;31m'
MAKE_IT_GREEN='\033[0;32m'
MAKE_IT_YELLOW='\033[0;33m'
MAKE_IT_BLUE='\033[0;34m'
MAKE_IT_CYAN='\033[0;36m'
MAKE_IT_WHITE='\033[0;37m'
MAKE_IT_MAGENTA='\033[0;35m'
RESET_COLOR='\033[0m' # Reset to default color

print_error() {
	if [[ -z "${2:-}" ]] || [[ "${2:-}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_RED}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_RED}${1}${RESET_COLOR}"
	fi
}

print_success() {
	if [[ -z "${2:-}" ]] || [[ "${2:-}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_GREEN}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_GREEN}${1}${RESET_COLOR}"
	fi
}

print_warning() {
	if [[ -z "${2:-}" ]] || [[ "${2:-}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_MAGENTA}[WARN] ${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_MAGENTA}[WARN] ${1}${RESET_COLOR}"
	fi
}

print_notify() {
	if [[ -z "${2:-}" ]] || [[ "${2:-}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_MAGENTA}[WARN] ${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_MAGENTA}[WARN] ${1}${RESET_COLOR}"
	fi
}

print_info() {
	if [[ -z "${2:-}" ]] || [[ "${2:-}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_WHITE}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_WHITE}${1}${RESET_COLOR}"
	fi
}

# Task-level operations (always use nskip to allow same-line completion)
print_task() {
	echo -ne "${MAKE_IT_CYAN}[TASK] ${1}${RESET_COLOR}"
}

print_task_done() {
	echo -e " ${MAKE_IT_GREEN}[DONE]${RESET_COLOR}"
}

print_task_fail() {
	echo -e " ${MAKE_IT_RED}[FAIL]${RESET_COLOR}"
}

print_task_skip() {
	echo -e " ${MAKE_IT_YELLOW}[SKIP]${RESET_COLOR}"
}

print_skip() {
	echo -e "${MAKE_IT_YELLOW}[SKIP] ${1}${RESET_COLOR}"
}

print_ready() {
	echo -e "${MAKE_IT_GREEN}[READY] ${1}${RESET_COLOR}"
}

print_summary() {
	echo -e "${MAKE_IT_CYAN}[SUMMARY] ${1}${RESET_COLOR}"
}