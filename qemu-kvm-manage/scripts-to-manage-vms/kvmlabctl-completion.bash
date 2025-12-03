#!/usr/bin/env bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
# Script Name : kvmlabctl-completion.bash
# Description : Bash completion script for kvmlabctl.sh
# Installation: Source this file in your ~/.bashrc or copy to /etc/bash_completion.d/
# Usage       : source kvmlabctl-completion.bash

_kvmlabctl_completions() {
    local cur prev subcommands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # All available subcommands
    subcommands="lab-start lab-health dnsbinder build-golden-image install-golden install-pxe reimage-golden reimage-pxe start stop shutdown restart reboot remove list console resize add-disk version"
    
    # Top-level options
    local options="-h --help -v --version"
    
    # If we're completing the first argument (subcommand)
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        if [[ ${cur} == -* ]]; then
            # Complete options
            COMPREPLY=( $(compgen -W "${options}" -- "${cur}") )
        else
            # Complete subcommands
            COMPREPLY=( $(compgen -W "${subcommands}" -- "${cur}") )
        fi
        return 0
    fi
    
    # If we're completing flags after a subcommand
    if [[ ${cur} == -* ]]; then
        COMPREPLY=( $(compgen -W "-h --help" -- "${cur}") )
        return 0
    fi
    
    return 0
}

# Register completion function for both kvmlabctl.sh and kvmlabctl (in case symlink exists)
complete -F _kvmlabctl_completions kvmlabctl.sh
complete -F _kvmlabctl_completions kvmlabctl
