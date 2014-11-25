imple backup script (remote version) It uses complete and                #
# incremental backups, with hard links to simulate snapshots.               #
# $FULL_BACKUP_LIMIT controls the frecuency of full backups.It accepts at   #
# least one source directory and a single destination directory (which must #
# be like user@host:directory) as arguments. Usage:                         #
#                                                                           #
# incremental_backup.sh SOURCE_DIRECTORY_1 [SOURCE_DIRECTORY_2..N]  	      #
#       DESTINATION_DIRECTORY                                               #
# todo: check if the log file exists. rotate                                #
#                                                                           #
#                                                                           #
#  Author: Álvaro Reig González                                             #
#  Licence: GNU GLPv3                                                       #    
#  www.alvaroreig.com                                                       #
#  https://github.com/alvaroreig                                            #
#############################################################################

DATE=`date +%Y%m%d` 
TIMESTAMP=$(date +%m%d%y%H%M%S) 
FULL_BACKUP_STRING=backup-full-$DATE-$TIMESTAMP
INC_BACKUP_STRING=backup-inc-$DATE-$TIMESTAMP
FULL_BACKUP_LIMIT=6
BACKUPS_TO_KEEP=21
EXCLUSSIONS="--exclude .cache/ --exclude .thumbnails/ --exclude .gvfs"
OPTIONS="-h -ab --stats -e ssh"
#To test the script, include "-n" to perform a 'dry' rsync

#############################################################################
# Arguments processing. The last argument is the destination directory, then#
# previous arguments are the source[s] directory[ies]                       #
#############################################################################

ARGS=("$@")

if [ ${#ARGS[*]} -lt 2 ]; then
  echo "At least two arguments are needed"
  echo "Usage: bash incremental_backup [SOURCE_DIR_1]...[SOURCE_DIR_N] [DESTINATION_DIR]"
  exit;
else

  # Store the destination directory
  DEST_DIR=${ARGS[${#ARGS[*]}-1]}

  # Store the first source directory
  SOURCE_DIRS=${ARGS[0]}
  let LAST_SOURCE_POSITION=${#ARGS[*]}-2
  SOURCE_COUNTER=1
  
  # Store the next source directories
  while [ $SOURCE_COUNTER -le $LAST_SOURCE_POSITION ]; do
    CURRENT_SOURCE_DIR=${ARGS[$SOURCE_COUNTER]-1]}
    let SOURCE_COUNTER=SOURCE_COUNTER+1
    SOURCE_DIRS=$SOURCE_DIRS" "$CURRENT_SOURCE_DIR
  done

  # Function to find out if a string contains a substring
  strindex() { 
  x="${1%%$2*}"
  [[ $x = $1 ]] && echo -1 || echo ${#x}
}

  # Check if the destination directory is like user@host:directory
  INDEX=`strindex "$DEST_DIR" ":"`
  DEST_DIR_LENGTH=`expr length $DEST_DIR`

  if [ $INDEX -eq -1 ]; then
    echo "Desination directory is not remote.Aborting."
    exit 0
  fi

  # Extracts from the DEST_DIR the SSH prefix and the "clean" destination directory 
  EXTRACTED_PREFIX=${DEST_DIR:0:INDEX}
  CLEAN_DEST_DIR=${DEST_DIR:INDEX+1:DEST_DIR_LENGTH}

  SSH_PREFIX="ssh $EXTRACTED_PREFIX"
  REMOTE_PREFIX="$EXTRACTED_PREFIX:"

  # Log parameters
  echo "[" `date +%Y-%m-%d_%R` "]" "###### Starting backup #######"
  echo "[" `date +%Y-%m-%d_%R` "]" "Directories to backup"  $SOURCE_DIRS
  echo "[" `date +%Y-%m-%d_%R` "]" "Destination directory"  $DEST_DIR
  echo "[" `date +%Y-%m-%d_%R` "]" "Limit to full backup:"  $FULL_BACKUP_LIMIT
  echo "[" `date +%Y-%m-%d_%R` "]" "Backups to keep:"       $BACKUPS_TO_KEEP
  echo "[" `date +%Y-%m-%d_%R` "]" "Extracted prefix:"      $EXTRACTED_PREFIX
  echo "[" `date +%Y-%m-%d_%R` "]" "Clean dest dir:"        $CLEAN_DEST_DIR
  echo "[" `date +%Y-%m-%d_%R` "]" "Exclussions:"           $EXCLUSSIONS
  echo "[" `date +%Y-%m-%d_%R` "]" "###### Browsing previous backups ######"
fi

############################################################################
# Browse previous backups                                                  #
############################################################################
BACKUPS=`$SSH_PREFIX ls -t $CLEAN_DEST_DIR |grep backup-`
BACKUP_COUNTER=0
BACKUPS_LIST=()

for x in $BACKUPS
do
  BACKUPS_LIST[$BACKUP_COUNTER]="$x"
  echo "[" `date +%Y-%m-%d_%R` "]" "backup detected:" ${BACKUPS_LIST[$BACKUP_COUNTER]}
  let BACKUP_COUNTER=BACKUP_COUNTER+1 

done

############################################################################
# Delete old backups, if necessary                                         #
############################################################################

echo "[" `date +%Y-%m-%d_%R` "]" "###### Deleting old backups ######"
echo "[" `date +%Y-%m-%d_%R` "]" "Number of previous backups: " ${#BACKUPS_LIST[*]}
echo "[" `date +%Y-%m-%d_%R` "]" "Backups to keep:"      $BACKUPS_TO_KEEP

###
if [ $BACKUPS_TO_KEEP -lt ${#BACKUPS_LIST[*]} ]; then
  let BACKUPS_TO_DELETE=${#BACKUPS_LIST[*]}-$BACKUPS_TO_KEEP
  echo "[" `date +%Y-%m-%d_%R` "]" "Need to delete" $BACKUPS_TO_DELETE" backups" $BACKUPS_TO_DELETE

  while [ $BACKUPS_TO_DELETE -gt 0 ]; do
    BACKUP=${BACKUPS_LIST[${#BACKUPS_LIST[*]}-1]}
    unset BACKUPS_LIST[${#BACKUPS_LIST[*]}-1]
    echo "[" `date +%Y-%m-%d_%R` "]" "Backup to delete:" $BACKUP
    $SSH_PREFIX  rm -rf $CLEAN_DEST_DIR"/"$BACKUP
    if [ $? -ne 0 ]; then
      echo "[" `date +%Y-%m-%d_%R` "]" "####### Error while deleting backup #######"
    else
      echo "[" `date +%Y-%m-%d_%R` "]" "Backup correctly deleted"
    fi
    let BACKUPS_TO_DELETE=BACKUPS_TO_DELETE-1
  done
else
  echo "[" `date +%Y-%m-%d_%R` "]" "No need to delete backups"  
fi


############################################################################
# The next backup will be complete if there is no full backup in the last  #
# FULL_BACKUP_LIMIT backups. If it is incremental, the last full backup    #
# will be used as a reference for the "--link-dest" option                 #
############################################################################

NEXT_BACKUP_FULL=true
COUNTER=0
LAST_FULL_BACKUP=

echo "[" `date +%Y-%m-%d_%R` "]" "###### Performing the backup ######"

while [[ $COUNTER -lt $FULL_BACKUP_LIMIT && $COUNTER -lt ${#BACKUPS_LIST[*]} ]]; do
  if [[ ${BACKUPS_LIST[$COUNTER]} == *full* ]]; then
  	NEXT_BACKUP_FULL=false;
  	LAST_FULL_BACKUP=${BACKUPS_LIST[$COUNTER]}
    echo "[" `date +%Y-%m-%d_%R` "]" "A full backup was performed" $COUNTER "backups ago which is less that the specified limit of" $FULL_BACKUP_LIMIT
    break;
  fi
  let COUNTER=COUNTER+1
done

############################################################################
# Finally, the backup is performed                                         #
############################################################################

# TODO list services to stop
if [ $NEXT_BACKUP_FULL == true ]; then
  echo "[" `date +%Y-%m-%d_%R` "]" "The backup will be full"
  echo "[" `date +%Y-%m-%d_%R` "]" "Stopping Services"
  rsync $OPTIONS $EXCLUSSIONS $SOURCE_DIRS $DEST_DIR/$FULL_BACKUP_STRING
else
  echo "[" `date +%Y-%m-%d_%R` "]" "The backup will be incremental"
  rsync $OPTIONS $EXCLUSSIONS --link-dest=$CLEAN_DEST_DIR/$LAST_FULL_BACKUP $SOURCE_DIRS $DEST_DIR/$INC_BACKUP_STRING
fi

############################################################################
# Log the backup status                                                    #
############################################################################

RETURN_STATUS=`$?`
if [ $RETURN_STATUS -ne "0" ]; then
  echo "[" `date +%Y-%m-%d_%R` "]" "####### Error during the backup. Please execute the script with the -v flag #######"
  echo "[" `date +%Y-%m-%d_%R` "]" "####### Error Code: $RETURN_STATUS. Please execute the script with the -v flag #######"
else
  echo "[" `date +%Y-%m-%d_%R` "]" "####### Backup correct #######"
fi
echo "[" `date +%Y-%m-%d_%R` "]" "Restarting Services"
# TODO list services to restart
