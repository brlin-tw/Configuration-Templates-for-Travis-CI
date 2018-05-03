#!/usr/bin/env bash
# shellcheck disable=SC2034

# Install the product into the system
# 林博仁 © 2018

## Makes debuggers' life easier - Unofficial Bash Strict Mode
## BASHDOC: Shell Builtin Commands - Modifying Shell Behavior - The Set Builtin
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

## Runtime Dependencies Checking
declare\
	runtime_dependency_checking_result=still-pass\
	required_software

for required_command in \
	basename\
	dirname\
	install\
	realpath\
	rm; do
	if ! command -v "${required_command}" &>/dev/null; then
		runtime_dependency_checking_result=fail

		case "${required_command}" in
			basename\
			|dirname\
			|install\
			|realpath\
			|rm)
				required_software='GNU Coreutils'
				;;
			*)
				required_software="${required_command}"
				;;
		esac

		printf --\
			'Error: This program requires "%s" to be installed and its executables in the executable searching paths.\n'\
			"${required_software}" 1>&2
		unset required_software
	fi
done; unset required_command required_software

if [ "${runtime_dependency_checking_result}" = fail ]; then
	printf --\
		'Error: Runtime dependency checking fail, the progrom cannot continue.\n' 1>&2
	exit 1
fi; unset runtime_dependency_checking_result

## Non-overridable Primitive Variables
## BASHDOC: Shell Variables » Bash Variables
## BASHDOC: Basic Shell Features » Shell Parameters » Special Parameters
if [ -v 'BASH_SOURCE[0]' ]; then
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
declare -ar RUNTIME_COMMANDLINE_ARGUMENTS=("${@}")

## init function: entrypoint of main program
## This function is called near the end of the file,
## with the script's command-line parameters as arguments
init(){
	local flag_uninstall=false
	local install_directory_xdg

	if ! process_commandline_arguments\
			flag_uninstall; then
		printf --\
			'Error: %s: Invalid command-line parameters.\n'\
			"${FUNCNAME[0]}"\
			1>&2
		print_help
		exit 1
	fi

	if ! determine_install_directory\
			install_directory_xdg; then
		printf -- \
			'Error: Unable to determine install directory, installer cannot continue.\n' \
			1>&2
		exit 1
	else
		printf -- \
			'Will be installed to: %s\n' \
			"${install_directory_xdg}"
		printf '\n'
	fi

	remove_old_installation\
		"${install_directory_xdg}"
	if [ "${flag_uninstall}" = true ]; then
		printf -- \
				'Software uninstalled successfully.\n'
		exit 0
	fi

	printf -- \
		'Installing template files...\n'
	install \
		--directory \
		--verbose \
		"${install_directory_xdg}"
	install \
		--mode='u=rw,go=r' \
		--verbose \
		"${RUNTIME_EXECUTABLE_DIRECTORY}/template.travis.yml" \
		"${install_directory_xdg}/travis.yml"
	printf '\n' # Seperate output from different operations

	while true; do
		printf -- \
			'Do you want to install files to enable KDE support(y/N)?'
		read -r answer

		if [ -z "${answer}" ]; then
			break
		else
			# lowercasewize
			answer="$(
				printf -- \
					'%s'\
					"${answer}"\
					| tr '[:upper:]' '[:lower:]'\
			)"

			if [ "${answer}" != n ] && [ "${answer}" != y ]; then
				# wrong format, re-ask
				continue
			elif [ "${answer}" == n ]; then
				break
			else
				printf 'Configuring templates for KDE...\n'
				install \
					--directory \
					--verbose \
					"${HOME}/.local/share/templates"
				install \
					--mode='u=rw,go=r' \
					--verbose \
					"${RUNTIME_EXECUTABLE_DIRECTORY}/template.travis.yml" \
					"${HOME}/.local/share/templates/travis.yml"
				install \
					--mode='u=rw,go=r' \
					--verbose \
					"${RUNTIME_EXECUTABLE_DIRECTORY}/Template Setup for KDE"/*.desktop \
					"${HOME}/.local/share/templates"
				break
			fi
		fi
	done; unset answer

	printf 'Installation completed.\n'


	exit 0
}; declare -fr init

print_help(){
	printf '# %s #\n' "${RUNTIME_EXECUTABLE_NAME}"
	printf 'This program installs the templates into the system to make it accessible.\n\n'

	printf '## Command-line Options ##\n'
	printf '### --help / -h ###\n'
	printf 'Print this message\n\n'

	printf '### --uninstall / -u ###\n'
	printf 'Instead of installing, attempt to remove previously installed product\n\n'

	printf '### --debug / -d ###\n'
	printf 'Enable debug mode\n\n'

	return 0
}; declare -fr print_help;

process_commandline_arguments() {
	local -n flag_uninstall_ref="${1}"

	if [ "${#RUNTIME_COMMANDLINE_ARGUMENTS[@]}" -eq 0 ]; then
		return 0
	fi

	# modifyable parameters for parsing by consuming
	local -a parameters=("${RUNTIME_COMMANDLINE_ARGUMENTS[@]}")

	# Normally we won't want debug traces to appear during parameter parsing, so we  add this flag and defer it activation till returning(Y: Do debug)
	local enable_debug=N

	while true; do
		if [ "${#parameters[@]}" -eq 0 ]; then
			break
		else
			case "${parameters[0]}" in
				--help\
				|-h)
					print_help;
					exit 0
					;;
				--uninstall\
				|-u)
					flag_uninstall_ref=true
					;;
				--debug\
				|-d)
					enable_debug=Y
					;;
				*)
					printf 'ERROR: Unknown command-line argument "%s"\n' "${parameters[0]}" >&2
					return 1
					;;
			esac
			# shift array by 1 = unset 1st then repack
			unset 'parameters[0]'
			if [ "${#parameters[@]}" -ne 0 ]; then
				parameters=("${parameters[@]}")
			fi
		fi
	done

	if [ "${enable_debug}" = Y ]; then
		trap 'trap_return "${FUNCNAME[0]}"' RETURN
		set -o xtrace
	fi
	return 0
}; declare -fr process_commandline_arguments

determine_install_directory(){
	local -n install_directory_xdg_ref="${1}"; shift

	# For $XDG_TEMPLATES_DIR
	if [ -f "${HOME}"/.config/user-dirs.dirs ];then
		# external file, disable check
		#shellcheck disable=SC1090
		source "${HOME}"/.config/user-dirs.dirs

		if [ -v XDG_TEMPLATES_DIR ]; then
			install_directory_xdg_ref="${XDG_TEMPLATES_DIR}"
			return 0
		fi
	fi

	printf -- \
		"%s: Warning: Installer can't locate user-dirs configuration, will fallback to unlocalized directories\\n" \
		"${FUNCNAME[0]}" \
		1>&2

	if [ ! -d "${HOME}"/Templates ]; then
		return 1
	else
		install_directory_xdg_ref="${HOME}"/Templates
	fi

}; declare -fr determine_install_directory

## Attempt to remove old installation files
remove_old_installation(){
	local install_directory_xdg="${1}"; shift 1

	printf 'Removing previously installed templates(if available)...\n'
	rm\
		--verbose\
		--force\
		"${install_directory_xdg}"/*travis.yml
	rm\
		--verbose\
		--force\
		"${HOME}/.local/share/templates"/*travis.yml\
		"${HOME}/.local/share/templates"/travis.yml.desktop
	printf 'Finished.\n'

	printf '\n' # Additional blank line for separating output
	return 0
}; declare -fr remove_old_installation

## Traps: Functions that are triggered when certain condition occurred
## Shell Builtin Commands » Bourne Shell Builtins » trap
trap_errexit(){
	printf 'An error occurred and the script is prematurely aborted\n' 1>&2
	return 0
}; declare -fr trap_errexit; trap trap_errexit ERR

trap_exit(){
	return 0
}; declare -fr trap_exit; trap trap_exit EXIT

trap_return(){
	local returning_function="${1}"

	printf 'DEBUG: %s: returning from %s\n' "${FUNCNAME[0]}" "${returning_function}" 1>&2
}; declare -fr trap_return

trap_interrupt(){
	printf '\n' # Separate previous output
	printf 'Recieved SIGINT, script is interrupted.' 1>&2
	return 1
}; declare -fr trap_interrupt; trap trap_interrupt INT

init "${@}"

## This script is based on the GNU Bash Shell Script Template project
## https://github.com/Lin-Buo-Ren/GNU-Bash-Shell-Script-Template
## and is based on the following version:
## GNU_BASH_SHELL_SCRIPT_TEMPLATE_VERSION="v3.0.0-4-g5de1348"
## You may rebase your script to incorporate new features and fixes from the template
