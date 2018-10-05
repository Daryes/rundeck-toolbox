#!/bin/bash
# -------------------------------------------------------------------------------------------
# script de sauvegarde d'une instance rundeck
# utilise rd-cli
#
# aide integree
# -------------------------------------------------------------------------------------------
# 2017/08/19	AHZ creation

DATE_SUFFIX=$( date '+%Y%m%d-%H%M%S' )

RUND_CONFIG_DIR=/etc/rundeck
RUND_TOOLDIR=/server/rundeck/tools
RUND_USER=rundeck
RUND_HOME=$( getent passwd ${RUND_USER}|cut -d ":" -f6 )


TMP_DIR=/tmp/$( basename $0 ).$$

BACKUP_DESC=$TMP_DIR/backup-structure.txt

BACKUP_DIR="$2"
BACKUP_FILE=rundeck-backup.${DATE_SUFFIX}.tar.gz


# loading env
. ${RUND_CONFIG_DIR}/profile || exit 1

# ----------------------------------------------------------------------------

# affichage sur stderr
echoerr() { printf "%s\n" "$*" >&2; }

# mise en format pour le fichier de description des elements a restaurer
outputDesc() {
	if [ $# -ne 2 ]; then exit 1; fi
	
	printf "%-40s =>  %s\n" "$1" "$2" >> $BACKUP_DESC
}

# ----------------------------------------------------------------------------
echo "RUNDECK BACKUP"
echo ""

if [ $# -ne 2 ] || [ "$1" != "-backup_dir" ]; then echoerr "Syntax: $(basename $0) -backup_dir < path >"; exit 1; fi 

# rundeck cli checks
if ! which rd > /dev/null; then echoerr "Error: rd command not found in the path"; echoerr "Current PATH=$PATH"; exit 1; fi
if ! rd scheduler > /dev/null; then echoerr "Error: cannot contact rundeck through rd-cli"; exit 1; fi

# checks
if [ ! -d "$RDECK_PROJECTS" ]; then echoerr "Error: $RDECK_PROJECTS not found"; exit 1; fi

echo "Command line used : $0 $*"
echo ""
echo "current user: $( whoami )"
echo "backup dir  : $BACKUP_DIR"
echo "temp dir    : $TMP_DIR"
echo "rundeck user: $RUND_USER"
echo "------------------------------------"

# temp dir check
if [ -d "$TMP_DIR" ]; then echoerr "Error: temp folder '$TMP_DIR' already exists"; exit 1; fi
mkdir -p "$TMP_DIR"/{jobs,etc-rundeck} || exit 1

# create backup dir
if [ ! -d "$BACKUP_DIR" ]; then mkdir -p "$BACKUP_DIR" || exit 1; fi


# backup project dir
echo ""
echo "backup: $RDECK_PROJECTS ..."
cp -ar "$RDECK_PROJECTS" "$TMP_DIR/projects"
outputDesc "projects" "$RDECK_PROJECTS"


# backup job definitions
echo ""
echo "backup: job definitions ..."
RUND_PROJECTS=$( rd projects list )
if [ $? -ne 0 ]; then exit 1; fi

RUND_PROJECTS=$( echo "$RUND_PROJECTS" | grep -v '^#' |grep -v "^ *$" )

while read -r sCurrentProject; do
	echo "=> Saving project $sCurrentProject ..."
	rd jobs list -f "$TMP_DIR/jobs/$sCurrentProject.xml" -p "$sCurrentProject"
	if [ $? -ne 0 ]; then exit 1; fi

	outputDesc "jobs/$sCurrentProject.xml" "rd jobs load -f \"jobs/$sCurrentProject.xml\" -p \"$sCurrentProject\" "
	
done <<< "$RUND_PROJECTS"	

# backup user keys
echo ""
echo "backup: user $RUND_USER ssh files ..."
cp -ar "$RUND_HOME/.ssh" "$TMP_DIR/"	|| exit 1
outputDesc ".ssh" "$RUND_HOME/.ssh"

# backup project ssh-keypath
echo ""
echo "backup: projects specific ssh-keypath files ..."
while read -r sCurrentData; do
	sCurrentKeypath_files=$( echo $sCurrentData | cut -d '=' -f2- )
	sCurrentKeypath_project=$( echo $sCurrentData | cut -d ':' -f1 | sed "s#$RDECK_PROJECTS/##g" | cut -d '/' -f1 )
	sCurrentKeypath_backdir="project_ssh-key/$sCurrentKeypath_project"
	
	# only archive if the files aren't already in HOME/.ssh
	if ! echo "$sCurrentKeypath_files" | grep -q "$RUND_HOME/.ssh"; then
		mkdir "$TMP_DIR/project_ssh-key/$sCurrentKeypath_project" &> /dev/null
		cp -a $sCurrentKeypath_files* $TMP_DIR/$sCurrentKeypath_backdir/ || exit 1	
		outputDesc "$sCurrentKeypath_backdir/*" "$( dirname $sCurrentKeypath_files )"
	fi
done < <( grep -uri 'project.ssh-keypath=' "$RDECK_PROJECTS" )


# backup tools dir
echo ""
echo "backup: tools directory ..."
cp -ar $RUND_TOOLDIR "$TMP_DIR/"        || exit 1
outputDesc "tools" "$RUND_TOOLDIR"


echo ""
echo "Creating archive: $BACKUP_DIR/$BACKUP_FILE ..."
tar czvf $BACKUP_DIR/$BACKUP_FILE -C "$TMP_DIR" . || exit 1

echo ""
echo "cleaning ..."
rm -r "$TMP_DIR"

echo ""
echo "Done."
