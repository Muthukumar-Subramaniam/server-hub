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
	if [[ -z "${2}" ]] || [[ "${2}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_RED}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_RED}${1}${RESET_COLOR}"
	fi
}

print_success() {
	if [[ -z "${2}" ]] || [[ "${2}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_GREEN}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_GREEN}${1}${RESET_COLOR}"
	fi
}

print_warning() {
	if [[ -z "${2}" ]] || [[ "${2}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_YELLOW}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_YELLOW}${1}${RESET_COLOR}"
	fi
}

print_info() {
	if [[ -z "${2}" ]] || [[ "${2}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_CYAN}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_CYAN}${1}${RESET_COLOR}"
	fi
}

print_notify() {
	if [[ -z "${2}" ]] || [[ "${2}" != "nskip" ]] 
	then
		echo -e "${MAKE_IT_WHITE}${1}${RESET_COLOR}"
	else
		echo -ne "${MAKE_IT_WHITE}${1}${RESET_COLOR}"
	fi
}