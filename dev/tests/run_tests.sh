#!/usr/bin/env bash

## obackup basic tests suite 2016090401

#TODO: Must recreate files before each test set

OBACKUP_DIR="$(pwd)"
OBACKUP_DIR=${OBACKUP_DIR%%/dev*}
DEV_DIR="$OBACKUP_DIR/dev"
TESTS_DIR="$DEV_DIR/tests"

if [ "$TRAVIS_RUN" == true ]; then
	echo "Running with travis settings"
	CONF_DIR="$TESTS_DIR/conf-travis"
else
	echo "Running with local settings"
	CONF_DIR="$TESTS_DIR/conf-local"
fi

LOCAL_CONF="local.conf"
PULL_CONF="pull.conf"
PUSH_CONF="push.conf"

OBACKUP_EXECUTABLE=obackup.sh

SOURCE_DIR="${HOME}/obackup-testdata"
TARGET_DIR="${HOME}/obackup-storage"

TARGET_DIR_SQL_LOCAL="$TARGET_DIR/sql"
TARGET_DIR_FILE_LOCAL="$TARGET_DIR/files"

TARGET_DIR_SQL_PULL="$TARGET_DIR/sql-pull"
TARGET_DIR_FILE_PULL="$TARGET_DIR/files-pull"

TARGET_DIR_SQL_PUSH="$TARGET_DIR/sql-push"
TARGET_DIR_FILE_PUSH="$TARGET_DIR/files-push"

TARGET_DIR_FILE_CRYPT="$TARGET_DIR/crypt"

SIMPLE_DIR="testData"
RECURSIVE_DIR="testDataRecursive"

S_DIR_1="dir rect ory"
R_EXCLUDED_DIR="Excluded"
R_DIR_1="a"
R_DIR_2="b"
R_DIR_3="c d"

S_FILE_1="some file"
R_FILE_1="file_1"
R_FILE_2="file 2"
R_FILE_3="file 3"
N_FILE_1="non recurse file"

EXCLUDED_FILE="exclu.ded"

DATABASE_1="mysql.sql.xz"
DATABASE_2="performance_schema.sql.xz"
DATABASE_EXCLUDED="information_schema.sql.xz"

CRYPT_EXTENSION=".obackup.gpg"
ROTATE_1_EXTENSION=".obackup.1"

PASSFILE="passfile"

function SetStableToYes () {
	if grep "^IS_STABLE=YES" "$OBACKUP_DIR/$OBACKUP_EXECUTABLE" > /dev/null; then
		IS_STABLE=yes
	else
		IS_STABLE=no
		sed -i.tmp 's/^IS_STABLE=no/IS_STABLE=yes/' "$OBACKUP_DIR/$OBACKUP_EXECUTABLE"
		assertEquals "Set stable to yes" "0" $?
	fi
}

function SetStableToOrigin () {
	if [ "$IS_STABLE" == "no" ]; then
		sed -i.tmp 's/^IS_STABLE=yes/IS_STABLE=no/' "$OBACKUP_DIR/$OBACKUP_EXECUTABLE"
		assertEquals "Set stable to origin value" "0" $?
	fi
}

function SetEncryption () {
	local confFile="${1}"
	local value="${2}"

	if [ $value == true ]; then
		sed -i 's/^ENCRYPTION=no/ENCRYPTION=yes/' "$confFile"
		assertEquals "Enable encryption in $file" "0" $?
	else
		sed -i 's/^ENCRYPTION=yes/ENCRYPTION=no/' "$confFile"
		assertEquals "Disable encryption in $file" "0" $?
	fi
}

function SetupGPG {
	if type gpg2 > /dev/null; then
		GPG=gpg2
	elif type gpg > /dev/null; then
		GPG=gpg
	else
		echo "No gpg support"
	fi

	if ! $GPG --list-keys | grep "John Doe" ; then

		cat >gpgcommand <<EOF
%echo Generating a GPG Key
Key-Type: RSA
Key-Length: 4096
Name-Real: John Doe
Name-Comment: obackup-test-key
Name-Email: john@example.com
Expire-Date: 0
Passphrase: PassPhrase123
# Do a commit here, so that we can later print "done" :-)
%commit
%echo done
EOF

		if type apt-get > /dev/null 2>&1; then
			apt-get install rng-tools
		fi

		# Setup fast entropy
		if type rngd > /dev/null 2>&1; then
			rngd -r /dev/urandom
		else
			echo "No rngd support"
		fi

		$GPG --batch --gen-key gpgcommand
		echo $($GPG --list-keys)
		rm -f gpgcommand

	fi

	echo "PassPhrase123" > "$TESTS_DIR/$PASSFILE"
}

function SetupSSH {
	echo -e  'y\n'| ssh-keygen -t rsa -b 2048 -N "" -f "${HOME}/.ssh/id_rsa_local"
	cat "${HOME}/.ssh/id_rsa_local.pub" >> "${HOME}/.ssh/authorized_keys"
	chmod 600 "${HOME}/.ssh/authorized_keys"

	# Add localhost to known hosts so self connect works
	if [ -z $(ssh-keygen -F localhost) ]; then
		ssh-keyscan -H localhost >> ~/.ssh/known_hosts
	fi
}

function oneTimeSetUp () {
	source "$DEV_DIR/ofunctions.sh"
	SetupGPG
	SetupSSH
}

function setUp () {
	rm -rf "$SOURCE_DIR"
	#rm -rf "$TARGET_DIR"

	mkdir -p "$SOURCE_DIR/$SIMPLE_DIR/$S_DIR_1"
	mkdir -p "$SOURCE_DIR/$RECURSIVE_DIR/$R_EXCLUDED_DIR"
	mkdir -p "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_1"
	mkdir -p "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_2"
	mkdir -p "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_3"

	touch "$SOURCE_DIR/$SIMPLE_DIR/$S_DIR_1/$S_FILE_1"
	touch "$SOURCE_DIR/$SIMPLE_DIR/$EXCLUDED_FILE"
	touch "$SOURCE_DIR/$RECURSIVE_DIR/$N_FILE_1"
	touch "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_1/$R_FILE_1"
	touch "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_2/$R_FILE_2"
	dd if=/dev/urandom of="$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_3/$R_FILE_3" bs=1M count=2
	touch "$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_3/$EXCLUDED_FILE"

	FilePresence=(
	"$SOURCE_DIR/$SIMPLE_DIR/$S_DIR_1/$S_FILE_1"
	"$SOURCE_DIR/$RECURSIVE_DIR/$N_FILE_1"
	"$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_1/$R_FILE_1"
	"$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_2/$R_FILE_2"
	"$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_3/$R_FILE_3"
	)

	DatabasePresence=(
	"$DATABASE_1"
	"$DATABASE_2"
	)

	FileExcluded=(
	"$SOURCE_DIR/$SIMPLE_DIR/$EXCLUDED_FILE"
	"$SOURCE_DIR/$RECURSIVE_DIR/$R_DIR_3/$R_EXCLUDED_FILE"
	)

	DatabaseExcluded=(
	"$DATABASE_EXCLUDED"
	)

	DirectoriesExcluded=(
	"$RECURSIVE_DIR/$R_EXCLUDED_DIR"
	)
}

function oneTimeTearDown () {
	SetStableToOrigin
}

function test_Merge () {
	cd "$DEV_DIR"
	./merge.sh
	assertEquals "Merging code" "0" $?
	SetStableToYes
}

function test_LocalRun () {
	# Basic return code tests. Need to go deep into file presence testing
	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$LOCAL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_LOCAL/$file" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_LOCAL/$file]" "0" $?
	done

	for file in "${FileExcluded[@]}"; do
		[ -f "$TARGET_DIR_FILE_LOCAL/$file" ]
		assertEquals "File Excluded [$TARGET_DIR_FILE_LOCAL/$file]" "1" $?
	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_LOCAL/$file" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_LOCAL/$file]" "0" $?
	done

	for file in "${DatabaseExcluded[@]}"; do
		[ -f "$TARGET_DIR_SQL_LOCAL/$file" ]
		assertEquals "Database Excluded [$TARGET_DIR_SQL_LOCAL/$file]" "1" $?
	done

	for directory in "${DirectoriesExcluded[@]}"; do
		[ -d "$TARGET_DIR_FILE_LOCAL/$directory" ]
		assertEquals "Directory Excluded [$TARGET_DIR_FILE_LOCAL/$directory]" "1" $?
	done

	# Tests presence of rotated files

	./$OBACKUP_EXECUTABLE "$CONF_DIR/$LOCAL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_LOCAL/$file$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_LOCAL/$file]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_LOCAL/$(dirname $SOURCE_DIR)$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence [$TARGET_DIR_FILE_LOCAL/$(dirname $SOURCE_DIR)$ROTATE_1_EXTENSION]" "0" $?

}

function test_PullRun () {
	# Basic return code tests. Need to go deep into file presence testing
	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PULL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_PULL/$file" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_PULL/$file]" "0" $?
	done

	for file in "${FileExcluded[@]}"; do
		[ -f "$TARGET_DIR_FILE_PULL/$file" ]
		assertEquals "File Excluded [$TARGET_DIR_FILE_PULL/$file]" "1" $?
	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PULL/$file" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_PULL/$file]" "0" $?
	done

	for file in "${DatabaseExcluded[@]}"; do
		[ -f "$TARGET_DIR_SQL_PULL/$file" ]
		assertEquals "Database Excluded [$TARGET_DIR_SQL_PULL/$file]" "1" $?
	done

	for directory in "${DirectoriesExcluded[@]}"; do
		[ -d "$TARGET_DIR_FILE_PULL/$directory" ]
		assertEquals "Directory Excluded [$TARGET_DIR_FILE_PULL/$directory]" "1" $?
	done

	# Tests presence of rotated files

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PULL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PULL/$file$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_PULL/$file]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_PULL/$(dirname $SOURCE_DIR)$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence" "0" $?

}

function test_PushRun () {
	# Basic return code tests. Need to go deep into file presence testing
	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PUSH_CONF"
	assertEquals "Return code" "0" $?

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_PUSH/$file" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_PUSH/$file]" "0" $?
	done

	for file in "${FileExcluded[@]}"; do
		[ -f "$TARGET_DIR_FILE_PUSH/$file" ]
		assertEquals "File Excluded [$TARGET_DIR_FILE_PUSH/$file]" "1" $?
	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PUSH/$file" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_PUSH/$file]" "0" $?
	done

	for file in "${DatabaseExcluded[@]}"; do
		[ -f "$TARGET_DIR_SQL_PUSH/$file" ]
		assertEquals "Database Excluded [$TARGET_DIR_SQL_PUSH/$file]" "1" $?
	done

	for directory in "${DirectoriesExcluded[@]}"; do
		[ -d "$TARGET_DIR_FILE_PUSH/$directory" ]
		assertEquals "Directory Excluded [$TARGET_DIR_FILE_PUSH/$directory]" "1" $?
	done

	# Tests presence of rotated files
	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PUSH_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PUSH/$file$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_PUSH/$file]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_PUSH/$(dirname $SOURCE_DIR)$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence" "0" $?

}

function test_EncryptLocalRun () {
	SetEncryption "$CONF_DIR/$LOCAL_CONF" true

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$LOCAL_CONF"

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_LOCAL/$file$CRYPT_EXTENSION" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_LOCAL/$file$CRYPT_EXTENSION]" "0" $?
	done

# TODO: Exclusion lists don't work with encrypted files yet
#	for file in "${FileExcluded[@]}"; do
#		[ -f "$TARGET_DIR_FILE_LOCAL/$file$CRYPT_EXTENSION" ]
#		assertEquals "File Excluded [$TARGET_DIR_FILE_LOCAL/$file$CRYPT_EXTENSION]" "1" $?
#	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION]" "0" $?
	done

#	for file in "${DatabaseExcluded[@]}"; do
#		[ -f "$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION" ]
#		assertEquals "Database Excluded [$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION]" "1" $?
#	done

#	for directory in "${DirectoriesExcluded[@]}"; do
#		[ -d "$TARGET_DIR_FILE_LOCAL/$directory" ]
#		assertEquals "Directory Excluded [$TARGET_DIR_FILE_LOCAL/$directory]" "1" $?
#	done


	# Tests presence of rotated files

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$LOCAL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_LOCAL/$file$CRYPT_EXTENSION$ROTATE_1_EXTENSION]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_LOCAL/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence [$TARGET_DIR_FILE_LOCAL/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION]" "0" $?

	SetEncryption "$CONF_DIR/$LOCAL_CONF" false

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_SQL_LOCAL" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt sql storage in [$TARGET_DIR_SQL_LOCAL]" "0" $?

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_FILE_CRYPT" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt file storage in [$TARGET_DIR_FILE_CRYPT]" "0" $?

}

function test_EncryptPullRun () {
	# Basic return code tests. Need to go deep into file presence testing
	SetEncryption "$CONF_DIR/$PULL_CONF" true

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PULL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_CRYPT/$file$CRYPT_EXTENSION" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_CRYPT/$file$CRYPT_EXTENSION]" "0" $?
	done

#	for file in "${FileExcluded[@]}"; do
#		[ -f "$TARGET_DIR_FILE_CRYPT/$file$CRYPT_EXTENSION" ]
#		assertEquals "File Excluded [$TARGET_DIR_FILE_PULL/$file$CRYPT_EXTENSION]" "1" $?
#	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION]" "0" $?
	done

#	for file in "${DatabaseExcluded[@]}"; do
#		[ -f "$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION" ]
#		assertEquals "Database Excluded [$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION]" "1" $?
#	done

#	for directory in "${DirectoriesExcluded[@]}"; do
#		[ -d "$TARGET_DIR_FILE_PULL/$directory" ]
#		assertEquals "Directory Excluded [$TARGET_DIR_FILE_PULL/$directory]" "1" $?
#	done

	# Tests presence of rotated files

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PULL_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_PULL/$file$CRYPT_EXTENSION$ROTATE_1_EXTENSION]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_CRYPT/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence [$TARGET_DIR_FILE_CRYPT/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION]" "0" $?

	SetEncryption "$CONF_DIR/$PULL_CONF" false

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_SQL_PULL" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt sql storage in [$TARGET_DIR_SQL_PULL]" "0" $?

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_FILE_CRYPT" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt file storage in [$TARGET_DIR_FILE_CRYPT]" "0" $?

}

function test_EncryptPushRun () {
	# Basic return code tests. Need to go deep into file presence testing
	SetEncryption "$CONF_DIR/$PUSH_CONF" true

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PUSH_CONF"
	assertEquals "Return code" "0" $?

	for file in "${FilePresence[@]}"; do
		[ -f "$TARGET_DIR_FILE_PUSH/$file$CRYPT_EXTENSION" ]
		assertEquals "File Presence [$TARGET_DIR_FILE_PUSH/$file$CRYPT_EXTENSION]" "0" $?
	done

#	for file in "${FileExcluded[@]}"; do
#		[ -f "$TARGET_DIR_FILE_PUSH/$file$CRYPT_EXTENSION" ]
#		assertEquals "File Excluded [$TARGET_DIR_FILE_PUSH/$file$CRYPT_EXTENSION]" "1" $?
#	done

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION" ]
		assertEquals "Database Presence [$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION]" "0" $?
	done

#	for file in "${DatabaseExcluded[@]}"; do
#		[ -f "$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION" ]
#		assertEquals "Database Excluded [$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION]" "1" $?
#	done

#	for directory in "${DirectoriesExcluded[@]}"; do
#		[ -d "$TARGET_DIR_FILE_PUSH/$directory" ]
#		assertEquals "Directory Excluded [$TARGET_DIR_FILE_PUSH/$directory]" "1" $?
#	done

	# Tests presence of rotated files

	cd "$OBACKUP_DIR"
	./$OBACKUP_EXECUTABLE "$CONF_DIR/$PUSH_CONF"
	assertEquals "Return code" "0" $?

	for file in "${DatabasePresence[@]}"; do
		[ -f "$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
		assertEquals "Database rotated Presence [$TARGET_DIR_SQL_PUSH/$file$CRYPT_EXTENSION]" "0" $?
	done

	[ -d "$TARGET_DIR_FILE_PUSH/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION" ]
	assertEquals "File rotated Presence [$TARGET_DIR_FILE_PUSH/$(dirname $SOURCE_DIR)$CRYPT_EXTENSION$ROTATE_1_EXTENSION]" "0" $?

	SetEncryption "$CONF_DIR/$PUSH_CONF" false

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_SQL_PUSH" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt sql storage in [$TARGET_DIR_SQL_PUSH]" "0" $?

	./$OBACKUP_EXECUTABLE --decrypt="$TARGET_DIR_FILE_PUSH" --passphrase-file="$TESTS_DIR/$PASSFILE"
	assertEquals "Decrypt file storage in [$TARGET_DIR_FILE_PUSH]" "0" $?
}

function test_WaitForTaskCompletion () {
	# Tests if wait for task completion works correctly

	# Standard wait
	sleep 1 &
	pids="$!"
	sleep 2 &
	pids="$pids;$!"
	WaitForTaskCompletion $pids 0 0 ${FUNCNAME[0]} true 0
	assertEquals "WaitForTaskCompletion test 1" "0" $?

	# Standard wait with warning
	sleep 2 &
	pids="$!"
	sleep 5 &
	pids="$pids;$!"

	WaitForTaskCompletion $pids 3 0 ${FUNCNAME[0]} true 0
	assertEquals "WaitForTaskCompletion test 2" "0" $?

	# Both pids are killed
	sleep 5 &
	pids="$!"
	sleep 5 &
	pids="$pids;$!"

	WaitForTaskCompletion $pids 0 2 ${FUNCNAME[0]} true 0
	assertEquals "WaitForTaskCompletion test 3" "2" $?

	# One of two pids are killed
	sleep 2 &
	pids="$!"
	sleep 10 &
	pids="$pids;$!"

	WaitForTaskCompletion $pids 0 3 ${FUNCNAME[0]} true 0
	assertEquals "WaitForTaskCompletion test 4" "1" $?

	# Count since script begin, the following should output two warnings and both pids should get killed
	sleep 20 &
	pids="$!"
	sleep 20 &
	pids="$pids;$!"

	WaitForTaskCompletion $pids 3 5 ${FUNCNAME[0]} false 0
	assertEquals "WaitForTaskCompletion test 5" "2" $?
}

function test_ParallelExec () {
	# Test if parallelExec works correctly

	cmd="sleep 2;sleep 2;sleep 2;sleep 2"
	ParallelExec 4 "$cmd"
	assertEquals "ParallelExec test 1" "0" $?

	cmd="sleep 2;du /none;sleep 2"
	ParallelExec 2 "$cmd"
	assertEquals "ParallelExec test 2" "1" $?

	cmd="sleep 4;du /none;sleep 3;du /none;sleep 2"
	ParallelExec 3 "$cmd"
	assertEquals "ParallelExec test 3" "2" $?
}

. "$TESTS_DIR/shunit2/shunit2"

