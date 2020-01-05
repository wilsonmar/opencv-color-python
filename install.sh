#!/usr/bin/env bash

# start.sh at https://github.com/wilsonmar/opencv-color-python/blob/master/install.sh
   # described at https://wilsonmar.github.io/opencv-color-python

# Here is an example of using Docker. Tested on macOS Mojave 10.14.
# If Docker is not installed, this script installs it, 
# This script also invokes Docker if it is not running,
# and stop Docker if requested.
# The app is cloned from GitHub.

# Copyright MIT license by Wilson Mar
# There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

### STEP 1. Set display utilities:

clear  # screen (but not history)

#set -eu pipefail  # pipefail counts as a parameter
# set -x to show commands for specific issues.
# set -o nounset
# set -e  # to end if 

# TEMPLATE: Capture starting timestamp and display no matter how it ends:
EPOCH_START="$(date -u +%s)"  # such as 1572634619
FREE_DISKBLOCKS_START="$(df -k . | cut -d' ' -f 6)"  # 910631000 Available

trap this_ending EXIT
trap this_ending INT QUIT TERM
this_ending() {
   echo "_"
   EPOCH_END=$(date -u +%s);
   DIFF=$((EPOCH_END-EPOCH_START))

   FREE_DISKBLOCKS_END="$(df -k . | cut -d' ' -f 6)"
   DIFF=$(((FREE_DISKBLOCKS_START-FREE_DISKBLOCKS_END)))
   MSG="End of script after $((DIFF/360)) minutes and $DIFF bytes disk space consumed."
   #   info 'Elapsed HH:MM:SS: ' $( awk -v t=$beg-seconds 'BEGIN{t=int(t*1000); printf "%d:%02d:%02d\n", t/3600000, t/60000%60, t/1000%60}' )
   success "$MSG"
   #note "$FREE_DISKBLOCKS_START to 
   #note "$FREE_DISKBLOCKS_END"
}
sig_cleanup() {
    trap '' EXIT  # some shells call EXIT after the INT handler.
    false # sets $?
    this_ending
}

### Set color variables (based on aws_code_deploy.sh): 
bold="\e[1m"
dim="\e[2m"
underline="\e[4m"
blink="\e[5m"
reset="\e[0m"
red="\e[31m"
green="\e[32m"
blue="\e[34m"
cyan="\e[36m"

h2() {     # heading
  printf "\n${bold}>>> %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
info() {   # output on every run
  printf "${dim}\n➜ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
RUN_VERBOSE=true
note() { if [ "${RUN_VERBOSE}" = true ]; then
   printf "${bold}${cyan} ${reset} ${cyan}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
   fi
}
success() {
  printf "${green}✔ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
error() {
  printf "${red}${bold}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnNotice() {
  printf "${cyan}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnError() {
  printf "${red}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}

info "Bash $BASH_VERSION"
# Check what operating system is used now.
if [ "$(uname)" == "Darwin" ]; then  # it's on a Mac:
   OS_TYPE="macOS"
elif [ -f "/etc/centos-release" ]; then
   OS_TYPE="CentOS"  # for yum
elif [ -f $( "lsb_release -a" ) ]; then  # TODO: Verify this works.
   OS_TYPE="Ubuntu"  # for apt-get
else 
   error "Operating system not anticipated. Please update script. Aborting."
   exit 0
fi
HOSTNAME=$( hostname )
info "OS_TYPE=$OS_TYPE on hostname=$HOSTNAME."


# h2 "STEP 1 - Ensure run variables are based on arguments or defaults ..."
args_prompt() {
   echo "This shell script edits a file (using sed) to trigger CI/CD upon git push."
   echo "USAGE EXAMPLE during testing (minimal inputs using defaults):"
   #echo "./start.sh -v -a"
   echo "OPTIONS:"
   echo "   -v       to run verbose"
   echo "   -a       for actual (not dry-run default)"
   echo "   -d       to delete container after run"
   echo "   -D       to delete app files after run"
   echo "   -X       to remove modules after run"  # RUN_REMOVE_DOCKER_AFTER
 }
#if [ $# -eq 0 ]; then  # display if no paramters are provided:
#   args_prompt
#fi
exit_abnormal() {  # Function: Exit with error.
  args_prompt
  exit 1
}
# Defaults:
RUNTYPE="upgrade"
BUILD_PATH="$HOME/gits"
REPO_ACCT="wilsonmar"
REPO_NAME="pyneo"
RESTART_DOCKER=false
CURRENT_IMAGE="testneo4j"
RUN_ACTUAL=false  # Not dry run
RUN_DELETE_AFTER=false
RUN_REMOVE_DOCKER_AFTER=false   # -X

while test $# -gt 0; do
  case "$1" in
    -h|-H|--help)
      args_prompt
      exit 0
      ;;
    -a)
      export RUN_ACTUAL=true
      shift
      ;;
    -r*)
      shift
      export RUNTYPE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -R)
      export RESTART_DOCKER=true
      shift
      ;;
    -b*)
      shift
      export BUILD_PATH=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -d)
      export RUN_DELETE_BEFORE=true
      shift
      ;;
    -D)
      export RUN_DELETE_AFTER=true
      shift
      ;;
    -p)
      export RUN_PROD=true
      shift
      ;;
    -u)
      shift
      export USER_EMAIL=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -v)
      export RUN_VERBOSE=true
      shift
      ;;
    -X)
      export RUN_REMOVE_DOCKER_AFTER=true
      shift
      ;;
    *)
      error "Parameter \"$1\" not recognized. Aborting."
      exit 0
      break
      ;;
  esac
done

command_exists() {  # newer than which {command}
  command -v "$@" > /dev/null 2>&1
}

#################

h2 "From file $0 in $PWD"

# TODO: Install Python.


if [[ "${RUNTYPE}" == *"upgrade"* ]]; then
   PIP_UPGRADE="--upgrade"
else
   PIP_UPGRADE=""
fi

# Per https://pypi.org/project/opencv-python/ remove OpenCV package in site packages:
OPENCV_VERSION="$( python3 -c 'import numpy; print(cv2.__version__)' )"  # or (numpy.version.version)
# See https://www.pyimagesearch.com/2015/08/10/checking-your-opencv-version-using-python/
if [[ "${OPENCV_VERSION}" == *"not defined"* ]]; then  # contains the string
   note "cv2 not installed. Continuing."
fi
#???      OPENCV_VERSION="$( python3 -c 'import opencv; print(cv2.__version__)' )"  # or (numpy.version.version)
   #if ...
      h2 "pip3 install opencv-python $OPENCV_VERSION with $PIP_UPGRADE ..."
      pip3 install "${PIP_UPGRADE}" opencv-python
         # opencv-python in /usr/local/lib/python3.7/site-packages (4.1.2.30)
         # This installs only main modules, not contrib modules in opencv-contrib-python
         # From https://pypi.org/project/opencv-python/ by Olli-Pekka Heinisuo (@skvark)
         # See https://docs.opencv.org/master/ for list of OpenCV modules and docs.
   #fi
   # echo "$( python3 -c 'import numpy; print(cv2.__version__)' )"  # or (cv2.version.version)
                                 # or cv2.show_config()
                                 # or pip freeze | grep 'cv2'

   NUMPY_VERSION="$( python3 -c 'import numpy; print(numpy.__version__)' )"  # or (numpy.version.version)
      h2 "pip3 install numpy with $NUMPY_VERSION ..."


      pip3 install "${PIP_UPGRADE}" opencv-python
   echo "$( python3 -c 'import numpy; print(numpy.__version__)' )"  # or (numpy.version.version)
                                 # or numpy.show_config()
                                 # or pip freeze | grep 'numpy'
   # Alternately, https://github.com/jrosebr1/imutils

python3 color_detection.py --image colorpic.jpg
   # At the lower-left corner, "(x=44, y=43)" is the position of the mouse.
   # "R:104 G:98 B:102" are the RGB values where the cursor is pointing.
