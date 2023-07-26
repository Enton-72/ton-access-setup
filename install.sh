#!/bin/bash
# Description: This script will prepare ton-access-setup Git project for deployment of docker containers.

HOME_DIR="$HOME"
SLACK_URL=""
SCRIPT_NAME=$(basename $0)
TON_ACCESS_DIR=""

send_slack () {
	curl -s -X POST $SLACK_URL -H 'Content-type: application/json' --data '{"text":"'"$(hostname): $1"'"}' >/dev/null
}
eecho() {
	echo -e "$@" 1>&2
	exit 1;
}
checkCronjob() {
	crontab -l|grep '#'$REPO_NAME''
}
installAccessSetup() {
	echo -n "[1/6] Creating config directory... "
	CONFIG_DIR="$REPO_DIR/ton-access/config"
	[ -d $CONFIG_DIR ] && rm -rf $CONFIG_DIR
	mkdir $CONFIG_DIR
	[ ! -d "$CONFIG_DIR" ] && eecho "Failed!"
	echo "Done"

	echo -n "[2/6] Downloading global-mainnet.json and global-testnet.json... "
	curl -sL https://ton-blockchain.github.io/global.config.json > $CONFIG_DIR/global-mainnet.json; [ $? -gt 0 ] && eecho "Error occurred while trying to download global-mainnet.json file!";
	curl -sL https://ton-blockchain.github.io/testnet-global.config.json > $CONFIG_DIR/global-testnet.json; [ $? -gt 0 ] && eecho "Error occurred while trying to download global-testnet.json file!";
	echo "Done"

	echo "[3/6] Generating local configuration file... "
	python3 /usr/src/mytonctrl/mytoninstaller.py <<< clcf >/dev/null
	[ $? -gt 0 ] && eecho "Failed!"
	echo "Done"

	echo -n "[4/6] Copying \"/usr/bin/ton/local.config.json\" in $HOME_DIR/ton-access/config/ ... "
	cp /usr/bin/ton/local.config.json $HOME_DIR/ton-access/config/
	[ $? -gt 0 ] && eecho "Failed!"
	echo "Done"

	echo -n "[5/6] Copying ton-access to $HOME_DIR... "
	TON_ACCESS_DIR="$HOME_DIR/ton-access"
 	[ -d $TON_ACCESS_DIR ] && rm -rf $TON_ACCESS_DIR
	cp -r ./ton-access $HOME_DIR ; [ $? -gt 0 ] && eecho "ton-access directory copy failed!";
	echo "Done"
	rm -rf $CONFIG_DIR

	echo -n "[6/6] Executing \"docker compose up -d\" in $HOME_DIR/ton-access as root... "
	cd $TON_ACCESS_DIR && sudo docker compose up -d
 	cd -
  	echo "Done"
}
USER=$(id -un)
[[ ! $USER == "ubuntu" ]] && eecho "Execute this script as \"ubuntu\" user.";
[ -z $(find . -type d -name ".git") ] && eecho "Execute this script inside of Git project."
[ $(docker ps &>/dev/null; echo $?) -gt 0 ] && eecho "User $USER is unable to execute docker commands!"
APPS="git python3 curl crontab docker mytonctrl"
declare -a DEPENDENCIES=()
for APP in $APPS
do
        command -v $APP > /dev/null 2>&1
        if [ ! $? -eq 0 ]
        then
                DEPENDENCIES+=$(echo -e "\n\t - $APP")
        fi
done
[ ! -z "$DEPENDENCIES" ] && eecho "Dependencies:$DEPENDENCIES\nInstall dependencies to continue."
REPO_DIR=$(git rev-parse --show-toplevel); [ -z "$REPO_DIR" ] && eecho "Unable to get full path of repository!"
REPO_NAME="$(basename $REPO_DIR)"; [ -z "$REPO_NAME" ] && eecho "Unable to get name of repository!"

### Main
cd $REPO_DIR
if [ $# -eq 0 ]
then
	installAccessSetup
	### Cron job installation
	JOB=$(checkCronjob)
	if [ -z "$JOB" ]; then
		echo -n "Installing cron job... "
		(crontab -l; echo -e '* * * * * /bin/bash -c '$HOME_DIR'/'$REPO_NAME'/install.sh --cron;#'$REPO_NAME'') | crontab -
		JOB=$(checkCronjob)
		[ -z "$JOB" ] && eecho "Failed to install cron job!"
		echo "Done"
	fi
elif [ "$1" == "--cron" ]
then
	FETCH=$(git fetch --dry-run 2>&1)
	[ -z "$FETCH" ] && exit 0;
	PULL=$(git pull)
	[[ $PULL =~ "Already up to date" ]] && send_slack "Nothing to pull from git!" && exit 0
	STATUS=$(git status --porcelain)
	[ ! -z "$STATUS" ] && send_slack "git status: $STATUS!"
	installAccessSetup
else
	eecho "Unknown variable!"
fi
