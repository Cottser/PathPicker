#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# get the directory of this script so we can execute the related python
# http://stackoverflow.com/a/246128/212110
SOURCE=$0
# resolve $SOURCE until the file is no longer a symlink
while [ -h "$SOURCE" ]; do
  BASEDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to
  # the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE="$BASEDIR/$SOURCE"
done
BASEDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

PYTHONCMD="python3"
NONINTERACTIVE=false

# Setup according to XDG/Freedesktop standards as specified by
# https://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html
if [ -z "$FPP_DIR" ]; then
  if [ -z "$XDG_CACHE_HOME" ]; then
    FPP_DIR="$HOME/.cache/fpp"
  else
    FPP_DIR="$XDG_CACHE_HOME/fpp"
  fi
fi

function doProgram {
  # process input from pipe and store as pickled file
  $PYTHONCMD "$BASEDIR/src/processInput.py" "$@"
  # if it failed, just fail now and exit the script
  # this works for the looping -ko case as well
  if [[ $? != 0 ]]; then exit $?; fi
  # now close stdin and choose input...
  exec 0<&-

  $PYTHONCMD "$BASEDIR/src/choose.py" "$@" < /dev/tty
  # Determine if running from within vim shell
  IFLAG=""
  if [ -z "$VIMRUNTIME" -a "$NONINTERACTIVE" = false ]; then
    IFLAG="-i"
  fi
  # execute the output bash script. For zsh or bash
  # shells, we delegate to $SHELL, but for all others
  # (fish, csh, etc) we delegate to bash.
  # For elvish shell, we always remove the -i flag.
  #
  # We use the following heuristics from
  # http://stackoverflow.com/questions/3327013/
  # in order to determine which shell we are on
  if ! [ -e "${SHELL}" ]; then
    (>&2 echo "Your SHELL bash variable ${SHELL} does not exist, please export it explicitly");
    $BASH $IFLAG "$FPP_DIR/.fpp.sh" < /dev/tty
  else
    case "$SHELL" in
      *zsh|*bash) $SHELL $IFLAG "$FPP_DIR/.fpp.sh" < /dev/tty;;
      # For elvish, don't pass the -i flag.
      *elvish) $SHELL "$FPP_DIR/.fpp.sh" < /dev/tty;;
      *) /bin/bash $IFLAG "$FPP_DIR/.fpp.sh" < /dev/tty
    esac
  fi
}

# we need to handle the --help option outside the python
# flow since otherwise we will move into input selection...
for opt in "$@"; do
  if [ "$opt" == "--debug" ]; then
    echo "Executing from '$BASEDIR'"
  elif [ "$opt" == "--version" ]; then
    VERSION="$($PYTHONCMD "$BASEDIR/src/version.py")"
    echo "fpp version $VERSION"
    exit 0
  elif [ "$opt" == "--python2" ]; then
    PYTHONCMD="python2"
  elif [ "$opt" == "--help" -o "$opt" == "-h" ]; then
    $PYTHONCMD "$BASEDIR/src/printHelp.py"
    exit 0
  elif [ "$opt" == "--record" -o "$opt" == "-r" ]; then
    echo "Recording input and output..."
  elif [ "$opt" == "--non-interactive" -o "$opt" == "-ni" ]; then
    NONINTERACTIVE=true
  elif [ "$opt" == "--keep-open" -o "$opt" == "-ko" ]; then
    # allow control-c to exit the loop
    # http://unix.stackexchange.com/a/48432
    trap "exit" INT
    while true; do
      doProgram "$@"
      # connect tty back to stdin since we closed it
      # earlier. this also works since we will only read
      # from stdin once and then go permanent interactive mode
      # http://stackoverflow.com/a/1992967/948126
      exec 0</dev/tty
    done
  fi
done

doProgram "$@"
