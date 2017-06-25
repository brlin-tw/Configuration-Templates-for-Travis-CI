#!/usr/bin/env bash
#shellcheck disable=SC2034

## Makes debuggers' life easier - Unofficial Bash Strict Mode
## BASHDOC: Shell Builtin Commands - Modifying Shell Behavior - The Set Builtin
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

## Non-overridable Primitive Variables
## BASHDOC: Shell Variables » Bash Variables
## BASHDOC: Basic Shell Features » Shell Parameters » Special Parameters
if [ -v "BASH_SOURCE[0]" ]; then
	RUNTIME_EXECUTABLE_PATH="$(realpath --strip "${BASH_SOURCE[0]}")"
	RUNTIME_EXECUTABLE_FILENAME="$(basename "${RUNTIME_EXECUTABLE_PATH}")"
	RUNTIME_EXECUTABLE_NAME="${RUNTIME_EXECUTABLE_FILENAME%.*}"
	RUNTIME_EXECUTABLE_DIRECTORY="$(dirname "${RUNTIME_EXECUTABLE_PATH}")"
	RUNTIME_COMMANDLINE_BASECOMMAND="${0}"
	declare -r\
		RUNTIME_EXECUTABLE_FILENAME\
		RUNTIME_EXECUTABLE_DIRECTORY\
		RUNTIME_EXECUTABLE_PATHABSOLUTE\
		RUNTIME_COMMANDLINE_BASECOMMAND
fi
declare -ar RUNTIME_COMMANDLINE_PARAMETERS=("${@}")

declare -i global_just_uninstall="1"

## init function: entrypoint of main program
## This function is called near the end of the file,
## with the script's command-line parameters as arguments
init(){
	
	local install_directory

	if ! process_commandline_parameters; then
		printf\
			"Error: %s: Invalid command-line parameters.\n"\
			"${FUNCNAME[0]}"\
			1>&2
		print_help
		exit 1
	fi

	if ! determine_install_directory install_directory; then
		printf "錯誤：無法判斷安裝目錄。安裝程式無法繼續運行\n" 1>&2
		exit "${COMMON_RESULT_FAILURE}"
	else
		printf "將會安裝到：%s\n" "install_directory"
		printf "\n"
	fi

	remove_old_installation
	if [ "${global_just_uninstall}" -eq "0" ]; then
		printf "已解除安裝軟體\n"
		exit "0"
	fi

	printf "正在安裝範本檔案……\n"
	cp\
		--force\
		--verbose\
		"${RUNTIME_EXECUTABLE_DIRECTORY}"/.travis.yml\
		"${XDG_TEMPLATES_DIR}"
	printf "\n" # Seperate output from different operations

	while :; do
		printf "請問是否安裝 KDE 所需的範本設定（警告：會造成 GNOME Files 等應用軟體中出現非預期的範本項目）(y/N)？"
		declare answer
		read -r answer

		if [ -z "${answer}" ]; then
			break
		else
			# lowercasewize
			answer="$(
				printf\
					"%s"\
					"${answer}"\
					| tr\
						"[:upper:]"\
						"[:lower:]"
			)"

			if [ "${answer}" != "n" ] && [ "${answer}" != "y" ]; then
				# wrong format, re-ask
				continue
			elif [ "${answer}" == "n" ]; then
				break
			else
				printf "正在設定適用於 KDE 的範本……\n"
				cp\
					--force\
					--verbose\
					"Template Setup for KDE/"*.desktop\
					"${XDG_TEMPLATES_DIR}"
				break
			fi
		fi
	done; unset answer

	printf "已完成安裝。\n"

	exit 0
}; declare -fr init

## Attempt to remove old installation files
remove_old_installation(){
	printf "正在清除過去安裝範本（如果有的話）……\n"
	rm --verbose --force "${XDG_TEMPLATES_DIR}"/.travis.yml || true
	printf "完成\n"

	printf "\n" # Additional blank line for separating output
	return "0"
}
readonly -f remove_old_installation

determine_install_directory(){
	local -n install_directory_ref="$1"

	# For $XDG_TEMPLATES_DIR
	if [ -f "${HOME}"/.config/user-dirs.dirs ];then
		# external file, disable check
		#shellcheck disable=SC1090
		source "${HOME}"/.config/user-dirs.dirs

		if [ -v XDG_TEMPLATES_DIR ]; then
			install_directory_ref="${XDG_TEMPLATES_DIR}"
			return "0"
		fi
	fi

	printf "%s - 警告 - 安裝程式找不到 user-dirs 設定，汰退到預設目錄\n" "${FUNCNAME[0]}"

	if [ ! -d "${HOME}"/Templates ]; then
		return "${COMMON_RESULT_FAILURE}"
	else
		install_directory_ref="${HOME}"/Templates
	fi

}; readonly -f determine_install_directory

## Traps: Functions that are triggered when certain condition occurred
## Shell Builtin Commands » Bourne Shell Builtins » trap
trap_errexit(){
	printf "An error occurred and the script is prematurely aborted\n" 1>&2
	return 0
}; declare -fr trap_errexit; trap trap_errexit ERR

trap_exit(){
	return 0
}; declare -fr trap_exit; trap trap_exit EXIT

trap_return(){
	local returning_function="${1}"

	printf "DEBUG: %s: returning from %s\n" "${FUNCNAME[0]}" "${returning_function}" 1>&2
}; declare -fr trap_return

trap_interrupt(){
	printf "Recieved SIGINT, script is interrupted.\n" 1>&2
	return 0
}; declare -fr trap_interrupt; trap trap_interrupt INT

print_help(){
	printf "Currently no help messages are available for this program\n" 1>&2
	return 0
}; declare -fr print_help;

process_commandline_parameters() {
	if [ "${#RUNTIME_COMMANDLINE_PARAMETERS[@]}" -eq 0 ]; then
		return 0
	fi

	# modifyable parameters for parsing by consuming
	local -a parameters=("${RUNTIME_COMMANDLINE_PARAMETERS[@]}")

	# Normally we won't want debug traces to appear during parameter parsing, so we  add this flag and defer it activation till returning(Y: Do debug)
	local enable_debug=N

	while true; do
		if [ "${#parameters[@]}" -eq 0 ]; then
			break
		else
			case "${parameters[0]}" in
				"--help"\
				|"-h")
					print_help;
					exit 0
					;;
				"--debug"\
				|"-d")
					enable_debug="Y"
					;;
				*)
					printf "ERROR: Unknown command-line argument \"%s\"\n" "${parameters[0]}" >&2
					return 1
					;;
			esac
			# shift array by 1 = unset 1st then repack
			unset "parameters[0]"
			if [ "${#parameters[@]}" -ne 0 ]; then
				parameters=("${parameters[@]}")
			fi
		fi
	done

	if [ "${enable_debug}" = "Y" ]; then
		trap 'trap_return "${FUNCNAME[0]}"' RETURN
		set -o xtrace
	fi
	return 0
}; declare -fr process_commandline_parameters;

init "${@}"

## This script is based on the GNU Bash Shell Script Template project
## https://github.com/Lin-Buo-Ren/GNU-Bash-Shell-Script-Template
## and is based on the following version:
declare -r META_BASED_ON_GNU_BASH_SHELL_SCRIPT_TEMPLATE_VERSION="v1.26.0-32-g317af27-dirty"
## You may rebase your script to incorporate new features and fixes from the template