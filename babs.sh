#!/bin/bash

#
# Copyright (c) 2024 by Mika Laitio <lamikr@gmail.com>
#
# License: GNU Lesser General Public License (LGPL), version 2.1 or later.
# See the lgpl.txt file in the root directory or <http://www.gnu.org/licenses/lgpl-2.1.html>.
#

source binfo/user_config.sh

func_is_user_in_dev_kfd_render_group() {
    if [ -e /dev/kfd ]; then
        test -w /dev/kfd || {
            echo ""
            echo "You need to set write permissions to /dev/kfd device driver for the user."
            echo "This /dev/kfd is used by the ROCM applications to communicate with the AMD GPUs"
            local group_owner_name=$(stat -c "%G" /dev/kfd)
            if [ ${group_owner_name} = "render" ]; then
                echo "Add your username to group render with command: "
                echo "    sudo adduser $USERNAME render"
                echo "Usually you need then reboot to get change to in permissions to take effect"
                return 2
            else
                echo "Unusual /dev/kfd group owner instead of 'render': ${group_owner_name}"
                echo "Add your username to group ${group_owner_name} with command: "
                echo "    sudo adduser $USERNAME ${group_owner_name}"
                echo "Usually you need then reboot to get change to in permissions to take effect"
                return 3
            fi
        }
    else
        echo "Warning, /dev/kfd AMD GPU device driver does not exist"
        return 4
    fi
    return 0
}

func_build_version_init() {
    local build_version_file="./binfo/build_version.sh"

    if [ -e "$build_version_file" ]; then
        source "$build_version_file"
    else
        echo "Error: Could not read $build_version_file"
        exit 1
    fi
}

func_envsetup_init() {
    local envsetup_file="./binfo/envsetup.sh"

    if [ -e "$envsetup_file" ]; then
        source "$envsetup_file"
    else
        echo "Error: Could not read $envsetup_file"
        exit 1
    fi
}

func_is_current_dir_a_git_submodule_dir() {
    if [ -f .gitmodules ]; then
        echo ".gitmodules file exists"
        if [ "$(wc -w < .gitmodules)" -gt 0 ]; then
            return 1
        else
            return 0
        fi
    else
        return 0
    fi
}

#if success function sets ret_val=0, in error cases ret_val=1
func_install_dir_init() {
    local ret_val

    ret_val=0
    if [ ! -z ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
        if [ -d ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
            if [ -w ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
                ret_val=0
            else
                echo "Warning, install direcory ${INSTALL_DIR_PREFIX_SDK_ROOT} is not writable for the user ${USER}"
                sudo chown $USER:$USER ${INSTALL_DIR_PREFIX_SDK_ROOT}
                if [ -w ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
                    echo "Install target directory owner changed with command 'sudo chown $USER:$USER ${INSTALL_DIR_PREFIX_SDK_ROOT}'"
                    sleep 10
                    ret_val=0
                else
                    echo "Recommend using command 'sudo chown ${USER}:${USER} ${INSTALL_DIR_PREFIX_SDK_ROOT}'"
                    ret_val=1
                fi
            fi
        else
            echo "Trying to create install target direcory: ${INSTALL_DIR_PREFIX_SDK_ROOT}"
            mkdir -p ${INSTALL_DIR_PREFIX_SDK_ROOT} 2> /dev/null
            if [ ! -d ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
                sudo mkdir -p ${INSTALL_DIR_PREFIX_SDK_ROOT}
                if [ -d ${INSTALL_DIR_PREFIX_SDK_ROOT} ]; then
                    echo "Install target directory created: 'sudo mkdir -p ${INSTALL_DIR_PREFIX_SDK_ROOT}'"
                    sudo chown $USER:$USER ${INSTALL_DIR_PREFIX_SDK_ROOT}
                    echo "Install target directory owner changed: 'sudo chown $USER:$USER ${INSTALL_DIR_PREFIX_SDK_ROOT}'"
                    sleep 10
                    ret_val=0
                else
                    echo "Failed to create install target directory: ${INSTALL_DIR_PREFIX_SDK_ROOT}"
                    ret_val=1
                fi
            else
                echo "Install target directory created: 'mkdir -p ${INSTALL_DIR_PREFIX_SDK_ROOT}'"
                sleep 10
                ret_val=0
            fi
        fi
    else
        echo "Error, environment variable not defined: INSTALL_DIR_PREFIX_SDK_ROOT"
        ret_val=1
    fi
    return ${ret_val}
}

func_is_current_dir_a_git_repo_dir() {
    local inside_git_repo
    inside_git_repo="$(git rev-parse --is-inside-work-tree 2>/dev/null)"
    if [ "$inside_git_repo" ]; then
        return 0  # is a git repo
    else
        return 1  # not a git repo
    fi
    #git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

func_repolist_binfo_list_print() {
    local jj=0

    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]; do
        echo "binfo appname:         ${LIST_BINFO_APP_NAME[jj]}"
        echo "binfo file short name: ${LIST_BINFO_FILE_BASENAME[jj]}"
        echo "binfo file full name:  ${LIST_BINFO_FILE_FULLNAME[jj]}"
        echo "src clone dir:         ${LIST_APP_SRC_CLONE_DIR[jj]}"
        echo "src dir:               ${LIST_APP_SRC_DIR[jj]}"
        echo "patch dir:             ${LIST_APP_PATCH_DIR[jj]}"
        echo "upstream repository:   ${LIST_APP_UPSTREAM_REPO_URL[jj]}"
        echo ""
        ((jj++))
    done
}

func_repolist_upstream_remote_repo_add() {
    local jj

    # Display a message if src_projects directory does not exist
    jj=0
    if [ ! -d src_projects ]; then
        echo ""
        echo "Download of source projects will start shortly"
        echo "It will take up about 20 gb under 'src_projects' directory."
        echo "Advice:"
        echo "If you work with multible copies of this sdk,"
        echo "you could tar 'src_projects' and extract it manually for other SDK copies."
        echo ""
        sleep 3
    fi
    # Initialize git repositories and add upstream remote
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ ! -d ${LIST_APP_SRC_CLONE_DIR[$jj]} ]; then
            echo "${jj}: Creating source code directory: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
            sleep 0.1
            mkdir -p ${LIST_APP_SRC_CLONE_DIR[$jj]}
            # LIST_APP_ADDED_UPSTREAM_REPO parameter is used in
            # situations where same src_code directory is used for building multiple projects
            # with just different configure parameters (for example amd-fftw)
            # in this case we want to add upstream repo and apply patches only once
            LIST_APP_ADDED_UPSTREAM_REPO[$jj]=1
        fi
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            if [ ! -d ${LIST_APP_SRC_CLONE_DIR[$jj]}/.git ]; then
                cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
                echo "${jj}: Initializing new source code repository"
                echo "Repository URL[$jj]: ${LIST_APP_UPSTREAM_REPO_URL[$jj]}"
                echo "Source directory[$jj]: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                echo "VERSION_TAG[$jj]: ${LIST_APP_UPSTREAM_REPO_VERSION_TAG[$jj]}"
                sleep 0.5
                git init
                echo ${LIST_APP_UPSTREAM_REPO_URL[$jj]}
                git remote add upstream ${LIST_APP_UPSTREAM_REPO_URL[$jj]}
                LIST_APP_ADDED_UPSTREAM_REPO[$jj]=1
            else
                LIST_APP_ADDED_UPSTREAM_REPO[$jj]=0
                echo "${jj}: ${LIST_APP_SRC_CLONE_DIR[$jj]} ok"
            fi
        else
            LIST_APP_ADDED_UPSTREAM_REPO[$jj]=0
            echo "${jj}: ${LIST_APP_SRC_CLONE_DIR[$jj]} ok"
        fi
        ((jj++))
        sleep 0.1
    done
    jj=0
    # Fetch updates and initialize submodules
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        #echo "LIST_APP_ADDED_UPSTREAM_REPO[$jj]: ${LIST_APP_ADDED_UPSTREAM_REPO[$jj]}"
        # check if directory was just created and git fetch needs to be done
        if [ ${LIST_APP_ADDED_UPSTREAM_REPO[$jj]} -eq 1 ]; then
            echo "${jj}: git fetch on ${LIST_APP_SRC_CLONE_DIR[$jj]}"
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            git fetch upstream
            if [ $? -ne 0 ]; then
                echo "git fetch failed: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                #exit 1
            fi
            git fetch upstream --force --tags
            git checkout "${LIST_APP_UPSTREAM_REPO_VERSION_TAG[$jj]}"
            func_is_current_dir_a_git_submodule_dir
            ret_val=$?
            if [ ${ret_val} == "1" ]; then
                echo "submodule init and update"
                git submodule update --init --recursive
                if [ $? -ne 0 ]; then
                    echo "git submodule init and update failed: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                    exit 1
                fi
            fi
        fi
        ((jj++))
    done
    jj=0
    # Apply patches if patch directory exists
    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]
    do
        #echo "LIST_APP_ADDED_UPSTREAM_REPO[$jj]: ${LIST_APP_ADDED_UPSTREAM_REPO[$jj]}"
        # check if directory was just created and git am needs to be done
        if [ ${LIST_APP_ADDED_UPSTREAM_REPO[$jj]} -eq 1 ]; then
            TEMP_PATCH_DIR=${LIST_APP_PATCH_DIR[$jj]}
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            echo "patch dir: ${TEMP_PATCH_DIR}"
            if [ -d "${TEMP_PATCH_DIR}" ]; then
                if [ ! -z "$(ls -A $TEMP_PATCH_DIR)" ]; then
                    echo "git am: ${LIST_BINFO_APP_NAME[${jj}]}"
                    git am --keep-cr "${TEMP_PATCH_DIR}"/*.patch
                    if [ $? -ne 0 ]; then
                        git am --abort
                        echo ""
                        echo "Failed to apply patches for repository"
                        echo "${LIST_APP_SRC_CLONE_DIR[${jj}]}"
                        echo "git am ${TEMP_PATCH_DIR[jj]}/*.patch failed"
                        echo ""
                        exit 1
                    else
                        echo "patches applied: ${LIST_APP_SRC_CLONE_DIR[${jj}]}"
                    fi
                else
                   echo "Warning, patch directory exists but is empty: ${TEMP_PATCH_DIR}"
                   sleep 2
                fi
            else
                true
                #echo "patch directory does not exist: ${TEMP_PATCH_DIR}"
                #sleep 2
            fi
        fi
        ((jj++))
    done
}

func_repolist_fetch_top_repo() {
    local jj

    jj=0
    echo "func_repolist_fetch_top_repo started"
    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            if [ -d ${LIST_APP_SRC_CLONE_DIR[$jj]} ]; then
                cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
                echo "Repository name: ${LIST_BINFO_APP_NAME[${jj}]}"
                echo "Repository URL[$jj]: ${LIST_APP_UPSTREAM_REPO_URL[$jj]}"
                echo "Source directory[$jj]: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                git fetch upstream
                if [ $? -ne 0 ]; then
                    echo "git fetch failed: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                    exit 1
                fi
                git fetch upstream --force --tags
            else
                echo ""
                echo "Failed to fetch source code for repository ${LIST_BINFO_APP_NAME[${jj}]}"
                echo "Source directory[$jj] not initialized with '-i' command:"
                echo "    ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                echo "Repository URL[$jj]: ${LIST_APP_UPSTREAM_REPO_URL[$jj]}"
                echo ""
                exit 1
            fi
        else
            echo "No repository defined for project in directory: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
        fi
        ((jj++))
    done
}

func_repolist_fetch_submodules() {
    local jj

    jj=0
    echo "func_repolist_fetch_submodules started"
    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]
    do
        cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
        if [ -f .gitmodules ]; then
            echo "submodule update"
            git submodule foreach git reset --hard
            git submodule update --recursive
            if [ $? -ne 0 ]; then
                echo "git submodule update failed: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
                exit 1
            fi
        fi
        ((jj++))
    done
}

func_repolist_checkout_default_versions() {
    local jj

    jj=0
    echo "func_repolist_checkout_default_versions started"
    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            echo "[$jj]: Repository to reset: ${LIST_BINFO_APP_NAME[${jj}]}"
            sleep 0.1
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            git reset --hard
            git checkout "${LIST_APP_UPSTREAM_REPO_VERSION_TAG[$jj]}"
        fi
        ((jj++))
    done
}

# check that repos does not
# - have uncommitted patches
# - have changes that diff from original patches
# - are not in state where am apply has failed
func_repolist_is_changes_committed() {
    local jj

    jj=0
    echo "func_repolist_is_changes_committed started"
    while [ "x${LIST_APP_PATCH_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            func_is_current_dir_a_git_repo_dir
            if [ $? -eq 0 ]; then
                if [[ `git status --porcelain --ignore-submodules=all` ]]; then
                    echo "git status error: " ${LIST_APP_SRC_CLONE_DIR[$jj]}
                    exit 1
                else
                    # No changes
                    #echo "git status ok: " ${LIST_APP_SRC_CLONE_DIR[$jj]}
                    #if [[ `git am --show-current-patch > /dev/null ` ]]; then
                    git status | grep "git am --skip" > /dev/null
                    if [ ! "$?" == "1" ]; then
                        echo "git am error: " ${LIST_APP_SRC_CLONE_DIR[$jj]}
                        exit 1
                    else
                        echo "git am ok: " ${LIST_APP_SRC_CLONE_DIR[$jj]}
                    fi
                fi
            else
                echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
            fi
        fi
        ((jj++))
    done
}

func_repolist_appliad_patches_save() {
    local jj

    jj=0
    cmd_diff_check=(git diff --exit-code)
    DATE=`date "+%Y%m%d"`
    DATE_WITH_TIME=`date "+%Y%m%d-%H%M%S"`
    PATCHES_DIR=$(pwd)/patches/${DATE_WITH_TIME}
    echo ${PATCHES_DIR}
    mkdir -p ${PATCHES_DIR}
    if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
        cd "${LIST_APP_SRC_CLONE_DIR[jj]}"
        func_is_current_dir_a_git_repo_dir
        if [ $? -eq 0 ]; then
            "${cmd_diff_check[@]}" &>/dev/null
            if [ $? -ne 0 ]; then
                fname=$(basename -- "${LIST_APP_SRC_CLONE_DIR[jj]}").patch
                echo "diff: ${fname}"
                "${cmd_diff_check[@]}" >${PATCHES_DIR}/${fname}
            else
                true
                #echo "${LIST_APP_SRC_CLONE_DIR[jj]}"
            fi
        else
            echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
        fi
    fi
    ((jj++))
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            cd "${LIST_APP_SRC_CLONE_DIR[jj]}"
            func_is_current_dir_a_git_repo_dir
            if [ $? -eq 0 ]; then
                "${cmd_diff_check[@]}" &>/dev/null
                if [ $? -ne 0 ]; then
                    fname=$(basename -- "${LIST_APP_SRC_CLONE_DIR[jj]}").patch
                    echo "diff: ${DATE_WITH_TIME}/${fname}"
                    "${cmd_diff_check[@]}" >${PATCHES_DIR}/${fname}
                else
                    true
                    #echo "${LIST_APP_SRC_CLONE_DIR[jj]}"
                fi
            else
                echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
            fi
        fi
        ((jj++))
    done
    echo "patches generated: ${PATCHES_DIR}"
}

func_repolist_export_version_tags_to_file() {
    local jj

    jj=0
    if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
        cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
        func_is_current_dir_a_git_repo_dir
        if [ $? -eq 0 ]; then
            GITHASH=$(git rev-parse --short=8 HEAD)
            echo "${GITHASH} ${LIST_BINFO_APP_NAME[${jj}]}" > ${FNAME_REPO_REVS_NEW}
        else
            echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
        fi
    fi
    ((jj++))
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            func_is_current_dir_a_git_repo_dir
            if [ $? -eq 0 ]; then
                GITHASH=$(git rev-parse --short=8 HEAD 2>/dev/null)
                echo "${GITHASH} ${LIST_BINFO_APP_NAME[${jj}]}" >> ${FNAME_REPO_REVS_NEW}
            else
                echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
            fi
        fi
        ((jj++))
    done
    echo "repo hash list generated: ${FNAME_REPO_REVS_NEW}"
}

func_repolist_find_app_index_by_app_name() {
    local temp_search_name="$1"
    local kk

    RET_INDEX_BY_NAME=-1
    kk=0
    while [[ -n "${LIST_BINFO_APP_NAME[kk]}" ]]; do
        if [[ "${LIST_BINFO_APP_NAME[kk]}" == "${temp_search_name}" ]]; then
            RET_INDEX_BY_NAME=$kk
            break
        fi
        ((kk++))
    done
}

func_repolist_fetch_by_version_tag_file() {
    echo "func_repolist_fetch_by_version_tag_file"

    if [ ! -z $1 ]; then
        REPO_UPSTREAM_NAME=$1
    else
        REPO_UPSTREAM_NAME=--all
    fi
    jj=0
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            echo "repo dir: ${LIST_APP_SRC_CLONE_DIR[$jj]}"
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            func_is_current_dir_a_git_repo_dir
            if [ $? -eq 0 ]; then
                echo "${LIST_BINFO_APP_NAME[jj]}: git fetch ${REPO_UPSTREAM_NAME}"
                git fetch ${REPO_UPSTREAM_NAME}
                if [ $? -ne 0 ]; then
                    echo "git fetch ${REPO_UPSTREAM_NAME} failed: " ${LIST_BINFO_APP_NAME[jj]}
                    #exit 1
                fi
                if [ -f .gitmodules ]; then
                    #echo "submodule update"
                    git submodule update --recursive
                fi
                sleep 1
            else
                echo "Not a git repository: " ${LIST_APP_SRC_CLONE_DIR[jj]}
                exit 1
            fi
        else
            echo "upstream fetch all skipped, no repository defined: " ${LIST_BINFO_APP_NAME[$jj]}
        fi
        ((jj++))
    done
}

func_repolist_version_tag_read_to_array_list_from_file() {
    echo "func_repolist_version_tag_read_to_array_list_from_file"

    LIST_REPO_REVS_CUR=()
    LIST_TEMP=()
    LIST_TEMP=(`cat "${FNAME_REPO_REVS_CUR}"`)
    echo "reading: ${FNAME_REPO_REVS_CUR}"
    jj=0
    while [ "x${LIST_TEMP[jj]}" != "x" ]
    do
        TEMP_HASH=${LIST_TEMP[$jj]}
        ((jj++))
        #echo "Element [$jj]: ${LIST_TEMP[$jj]}"
        TEMP_NAME=${LIST_TEMP[$jj]}
        #echo "Element [$jj]: ${TEMP_NAME}"
        func_repolist_find_app_index_by_app_name ${TEMP_NAME}
        if [ ${RET_INDEX_BY_NAME} -ge 0 ]; then
            LIST_REPO_REVS_CUR[$RET_INDEX_BY_NAME]=${TEMP_HASH}
            if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$RET_INDEX_BY_NAME]]}" == "1" ]; then
                echo "find_index_by_name ${TEMP_NAME}: " ${LIST_REPO_REVS_CUR[$RET_INDEX_BY_NAME]} ", repo: " ${LIST_APP_UPSTREAM_REPO_URL[$RET_INDEX_BY_NAME]}
            fi
        else
            echo "Find_index_by_name failed for name: " ${TEMP_NAME}
            exit 1
        fi
        ((jj++))
    done
}

func_repolist_checkout_by_version_tag_file() {
    echo "func_repolist_checkout_by_version_tag_file"
    func_repolist_fetch_by_version_tag_file

    # Read hashes from the stored txt file
    func_repolist_version_tag_read_to_array_list_from_file
    jj=0
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
            cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
            func_is_current_dir_a_git_repo_dir
            if [ $? -eq 0 ]; then
                echo "git checkout: " ${LIST_BINFO_APP_NAME[jj]}
                git checkout ${LIST_REPO_REVS_CUR[$jj]}
                if [ $? -ne 0 ]; then
                    echo "repo checkout failed: " ${LIST_BINFO_APP_NAME[jj]}
                    echo "    revision: " ${LIST_REPO_REVS_CUR[$jj]}
                    exit 1
                else
                    echo "repo checkout ok: " ${LIST_BINFO_APP_NAME[jj]}
                    echo "    revision: " ${LIST_REPO_REVS_CUR[$jj]}
                fi
            else
                echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
            fi
        else
            echo "upstream repo checkout skipped, no repository defined: " ${LIST_BINFO_APP_NAME[$jj]}
        fi
        ((jj++))
    done
}

func_repolist_apply_patches() {
    declare -A DICTIONARY_PATCHED_PROJECTS
    echo "func_repolist_apply_patches"
    jj=0
    while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
    do
        if [ -z ${DICTIONARY_PATCHED_PROJECTS[${LIST_BINFO_APP_NAME[${jj}]}]} ]; then
            if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
                cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
                func_is_current_dir_a_git_repo_dir
                if [ $? -eq 0 ]; then
                    TEMP_PATCH_DIR=${LIST_APP_PATCH_DIR[$jj]}
                    echo "patch dir: ${TEMP_PATCH_DIR}"
                    if [ -d "${TEMP_PATCH_DIR}" ]; then
                        if [ ! -z "$(ls -A $TEMP_PATCH_DIR)" ]; then
                            echo "[$jj]: ${LIST_BINFO_APP_NAME[${jj}]}: applying patches"
                            sleep 0.1
                            git am --keep-cr "${TEMP_PATCH_DIR}"/*.patch
                            if [ $? -ne 0 ]; then
                                git am --abort
                                echo ""
                                echo "repository: ${LIST_APP_SRC_CLONE_DIR[${jj}]}"
                                echo "git am ${TEMP_PATCH_DIR[jj]}/*.patch failed"
                                echo ""
                                exit 1
                            else
                                echo "patches applied: ${LIST_APP_SRC_CLONE_DIR[${jj}]}"
                                #echo "git am ok"
                            fi
                            DICTIONARY_PATCHED_PROJECTS[${LIST_BINFO_APP_NAME[${jj}]}]=1
                        else
                            echo "Warning, empty patch directory: ${TEMP_PATCH_DIR}"
                            sleep 2
                        fi
                    else
                        true
                        echo "${LIST_BINFO_APP_NAME[${jj}]}: No patches to apply"
                        #echo "patch directory does not exist: ${TEMP_PATCH_DIR}"
                        #sleep 2
                    fi
                    sleep 0.1
                else
                    echo "Warning, not a git repository: ${LIST_APP_SRC_CLONE_DIR[${jj}]}"
                    sleep 2
                fi
            else
                echo "repo am paches skipped, no repository defined: ${LIST_BINFO_APP_NAME[${jj}]}"
            fi
        else
            echo "[$jj]: ${LIST_BINFO_APP_NAME[${jj}]}: patches already applied, skipping"
        fi
        ((jj++))
    done
}

func_repolist_checkout_by_version_param() {
    if [ ! -z $1 ]; then
        CHECKOUT_VERSION=$1
        echo "func_repolist_checkout_by_version_param: ${CHECKOUT_VERSION}"
        jj=0
        while [ "x${LIST_APP_SRC_CLONE_DIR[jj]}" != "x" ]
        do
            if [ "${LIST_APP_UPSTREAM_REPO_DEFINED[$jj]}" == "1" ]; then
                cd "${LIST_APP_SRC_CLONE_DIR[$jj]}"
                func_is_current_dir_a_git_repo_dir
                if [ $? -eq 0 ]; then
                    #echo "git checkout ${CHECKOUT_VERSION}: ${LIST_BINFO_APP_NAME[jj]}"
                    git checkout ${CHECKOUT_VERSION}
                    if [ $? -ne 0 ]; then
                        echo "git checkout failed: " ${LIST_BINFO_APP_NAME[jj]}
                        echo "   version: " ${CHECKOUT_VERSION}
                    else
                        true
                        #echo "repo checkout ok: " ${LIST_BINFO_APP_NAME[jj]}
                        #echo "   version: " ${CHECKOUT_VERSION}
                    fi
                else
                    echo "Not a git repo: " ${LIST_APP_SRC_CLONE_DIR[jj]}
                fi
            else
                echo "upstream repo checkout skipped, no repository defined: " ${LIST_BINFO_APP_NAME[$jj]}
            fi
            ((jj++))
        done
    else
        echo "    Error, git version parameter missing"
        exit
    fi
}

#this method not used at the moment and needs refactoring if needed in future
func_repolist_download() {
    func_build_version_init
    func_envsetup_init
    func_repolist_binfo_list_print
    func_repolist_upstream_remote_repo_add
    func_repolist_is_changes_committed
}

func_env_variables_print() {
    echo "SDK_CXX_COMPILER_DEFAULT: ${SDK_CXX_COMPILER_DEFAULT}"
    echo "HIP_PLATFORM_DEFAULT: ${HIP_PLATFORM_DEFAULT}"
    echo "HIP_PLATFORM: ${HIP_PLATFORM}"
    echo "HIP_PATH: ${HIP_PATH}"

    echo "SDK_ROOT_DIR: ${SDK_ROOT_DIR}"
    echo "SDK_SRC_ROOT_DIR: ${SDK_SRC_ROOT_DIR}"
    echo "BUILD_RULE_ROOT_DIR: ${BUILD_RULE_ROOT_DIR}"
    echo "PATCH_FILE_ROOT_DIR: ${PATCH_FILE_ROOT_DIR}"
    echo "BUILD_ROOT_DIR: ${BUILD_ROOT_DIR}"
    echo "INSTALL_DIR_PREFIX_SDK_ROOT: ${INSTALL_DIR_PREFIX_SDK_ROOT}"
    echo "INSTALL_DIR_PREFIX_HIPCC: ${INSTALL_DIR_PREFIX_HIPCC}"
    echo "INSTALL_DIR_PREFIX_HIP_CLANG: ${INSTALL_DIR_PREFIX_HIP_CLANG}"
    echo "INSTALL_DIR_PREFIX_C_COMPILER: ${INSTALL_DIR_PREFIX_C_COMPILER}"
    echo "INSTALL_DIR_PREFIX_HIP_LLVM: ${INSTALL_DIR_PREFIX_HIP_LLVM}"

    echo "SPACE_SEPARATED_GPU_TARGET_LIST_DEFAULT: ${SPACE_SEPARATED_GPU_TARGET_LIST_DEFAULT}"
    echo "SEMICOLON_SEPARATED_GPU_TARGET_LIST_DEFAULT: $SEMICOLON_SEPARATED_GPU_TARGET_LIST_DEFAULT"
    echo "LF_SEPARATED_GPU_TARGET_LIST_DEFAULT: $LF_SEPARATED_GPU_TARGET_LIST_DEFAULT"
    echo "HIP_PATH_DEFAULT: ${HIP_PATH_DEFAULT}"
}

func_build_system_name_and_version_print() {
    echo "babs version: ${BABS_VERSION:-unknown}"
    echo "sdk version: ${ROCM_SDK_VERSION_INFO:-unknown}"
}

func_user_help_print() {
    func_build_system_name_and_version_print
    echo "babs (babs ain't patch build system)"
    echo "usage:"
    echo "-h or --help:           Show this help"
    echo "-c or --configure       Show list of GPU's for which the the build is optimized"
    echo "-i or --init:           Download git repositories listed in binfo directory to 'src_projects' directory"
    echo "                        and apply all patches from 'patches' directory."
    echo "-ap or --apply_patches: Scan 'patches/rocm-version' directory and apply each patch"
    echo "                        on top of the repositories in 'src_projects' directory."
    echo "-co or --checkout:      Checkout version listed in binfo files for each git repository in src_projects directory."
    echo "                        Apply of patches of top of the checked out version needs to be performed separately"
    echo "                        with '-ap' command."
    echo "-f or --fetch:          Fetch latest source code for all repositories."
    echo "                        Checkout of fetched sources needs to be performed separately with '-co' command."
    echo "                        Possible subprojects needs to be fetched separately with '-fs' command. (after '-co' and '-ap')"
    echo "-fs or --fetch_submod:  Fetch and checkout git submodules for all repositories which have them."
    echo "-b or --build:          Start or continue the building of rocm_sdk."
    echo "                        Build files are located under 'builddir' directory and install is done under '/opt/rocm_sdk_version' directory."
    echo "-v or --version:        Show babs build system version information"
    #echo "-cp or --create_patches: generate patches by checking git diff for each repository"
    #echo "-g or --generate_repo_list: generates repo_list_new.txt file containing current repository revision hash for each project"
    #echo "-s or --sync: checkout all repositories to base git hash"
    echo ""
    if [ ! -d src_projects ]; then
        echo ""
        echo "----------------Advice ---------------"
        echo "No ROCm project source codes detected in 'src_projects 'directory."
        echo "I recommend downloading them first with command './babs.sh -i'"
        echo ""
        echo "Projects will be loaded to 'src_projects' directory"
        echo "and will require about 20gb of space."
        echo "If download of some projects fails, you can issue './babs.sh -i' command again"
        echo "--------------------------------------"
        echo ""
    else
        if [ ! -d builddir ]; then
        echo ""
        echo "----------------Advice ---------------"
        echo "No ROCm 'builddir' directory detected."
        echo "Once projects source code has been downloaded with './babs.sh -i' command"
        echo "you can start building with command './babs.sh -b'"
        echo "--------------------------------------"
        echo ""
        fi
    fi
    exit 0
}

func_is_git_configured() {
    local GIT_USER_NAME
    local GIT_USER_EMAIL

    GIT_USER_NAME=$(git config --get user.name)
    if [[ -n "$GIT_USER_NAME" ]]; then
        GIT_USER_EMAIL=$(git config --get user.email)
        if [[ -n "$GIT_USER_EMAIL" ]]; then
            return 0
        else
            echo ""
            echo "You need to configure git user's email address. Example command:"
            echo "    git config --global user.email \"john.doe@emailserver.com\""
            echo ""
            exit 2
        fi
    else
        echo ""
        echo "You need to configure git user's name and email address. Example commands:"
        echo "    git config --global user.name \"John Doe\""
        echo "    git config --global user.email \"john.doe@emailserver.com\""
        echo ""
        exit 2
    fi
}

func_handle_user_configure_help_and_version_args() {
    for arg in "${LIST_USER_CMD_ARGS[@]}"; do
        case $arg in
            -c|--configure)
                func_build_cfg_user
                exit 0
                ;;
            -h|--help)
                func_user_help_print
                exit 0
                ;;
            -v|--version)
                func_build_system_name_and_version_print
                exit 0
                ;;
        esac
    done
}

func_handle_user_command_args() {
    local ii=0

    while [[ -n "${LIST_USER_CMD_ARGS[ii]}" ]]; do
        case "${LIST_USER_CMD_ARGS[ii]}" in
            -ap|--apply_patches)
                func_is_git_configured
                func_repolist_apply_patches
                echo "Patches applied to git repositories"
                exit 0
                ;;
            -b|--build)
                func_env_variables_print
                func_install_dir_init
                local ret_val=$?
                if [[ $ret_val -eq 0 ]]; then
                    ./build/build.sh
                    local res=$?
                    if [[ $res -eq 0 ]]; then
                        echo -e "\nROCM SDK build and install ready"
                        func_is_user_in_dev_kfd_render_group
                        res=$?
                        if [ ${res} -eq 0 ]; then
                            echo "You can use the following commands to test your gpu is detected:"
                        else
                            echo "After fixing /dev/kff permission problems, you can use the following commands to test that your gpu"
                        fi
                        echo ""
                        echo "    source ${INSTALL_DIR_PREFIX_SDK_ROOT}/bin/env_rocm.sh"
                        echo "    rocminfo"
                        echo ""
                    else
                        echo -e "Build failed"
                    fi
                    exit 0
               else
                    echo "Failed to initialize install directory"
                    exit 1
               fi
               ;;
            -cp|--create_patches)
                func_repolist_appliad_patches_save
                exit 0
                ;;
            -co|--checkout)
                func_repolist_checkout_default_versions
                exit 0
                ;;
            -f|--fetch)
                func_repolist_fetch_top_repo
                exit 0
                ;;
            -fs|--fetch_submod)
                func_repolist_fetch_submodules
                exit 0
                ;;
            -g|--generate_repo_list)
                func_repolist_export_version_tags_to_file
                exit 0
                ;;
            -i|--init)
                func_is_git_configured
                func_repolist_upstream_remote_repo_add
                echo "All git repositories initialized"
                exit 0
                ;;
            -s|--sync)
                func_repolist_checkout_by_version_tag_file
                exit 0
                ;;
            *)
                echo "Unknown user command parameter: ${LIST_USER_CMD_ARGS[ii]}"
                 exit 0
                 ;;
        esac
        ((ii++))
    done
}

if [ "$#" -eq 0 ]; then
    func_user_help_print
else
    LIST_USER_CMD_ARGS=( "$@" )
    # Initialize build version
    func_build_version_init
    # Handle help and version commands before prompting the user config menu
    func_handle_user_configure_help_and_version_args
    # Initialize environment setup
    func_envsetup_init
    # Handle user command arguments
    func_handle_user_command_args
fi
