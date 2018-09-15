#!/bin/bash


#####
### Root to install
#####
if [ "$(whoami &2>/dev/null)" != "root" ] && [ "$(id -un &2>/dev/null)" != "root" ]
then
  echo "You must be root to run this script!"
  echo "use 'sudo !!'"
  exit 1
fi
#####
### Set UserName
#####
echo "Ready to start"
read -rp 'UserName: ' uservar
echo "Nice $uservar"
#####
### Set User Groups
#####
USER=$uservar
GROUP=$uservar
#####
### Variables
#####

source take
chmod +x take
FILE_LIST="/home/$USER/.config/rclone/rclone.conf /etc/systemd/system/rclonemount.service /etc/systemd/system/mergerfs.service /home/$USER/scripts/rclone-upload.sh"  # Space separated list of files to backup (include full path to file)
KEEP_OLD="10"  # How many previous versions to keep
#####
### Create directories for install
#####
mkdir /home/$USER/mergerfs >/dev/null 2>&1
sudo -u $USER mkdir -p /home/$USER/{mnt/{move,gdrive,media},.config/rclone,scripts/logs} >/dev/null 2>&1
sudo -u $USER mkdir -p /home/$USER/.config/qBittorrent/ >/dev/null 2>&1
#####
#####
### Functions
#####

function shift_backups {
  for num in $(seq $KEEP_OLD -1 1) ; do
    old_backup="$file.bak$num"
    if [[ -e $old_backup && $num == $KEEP_OLD ]] ; then
      echo "    removing oldest file ($old_backup)" >/dev/null 2>&1
      rm -f $old_backup
    elif [[ -e $old_backup ]] ; then
      new_name="$file.bak$(expr $num + 1)"
      echo "    moving $old_backup to $new_name" >/dev/null 2>&1
      mv $old_backup $new_name
    fi
  done
}
#####
### Backup Files
#####
for file in $FILE_LIST ; do
  count=1
  while [[ $count -le $KEEP_OLD ]] ; do
    backup_file="$file.bak$count"
    if [[ -e $backup_file ]] ; then
      echo "$backup_file exists, shifting backups" >/dev/null 2>&1
      shift_backups
      cp $file $backup_file >/dev/null 2>&1
      break
    else
      cp $file $backup_file >/dev/null 2>&1
      break
    fi
    count=$(expr $count + 1)
  done
done
if [[ -f $FILE_LIST ]]; then
  rm $FILE_LIST
  echo "Old files deleted"
fi
clear
#####
### Install Programs
#####
{
  if command -v curl >/dev/null 2>&1; then
    echo "Curl er Installert"
  else
    echo "Installer curl"
    sudo apt -y install curl >/dev/null 2>&1
  fi
  sleep 3

  if command -v unzip >/dev/null 2>&1; then
    echo "Unzip er Installeret"
  else
    echo "Installer unzip"
    sudo apt -y install unzip >/dev/null 2>&1

  fi
  sleep 3
  if command -v fuser >/dev/null 2>&1; then
    echo "Fuse er Installeret"
  else
    echo "Installer Fuse"
    apt -y install fuse >/dev/null 2>&1
  fi
  sleep 3
  clear
  if command -v rclone >/dev/null 2>&1; then
    echo "Rclone er Installeret"
  else
    curl https://rclone.org/install.sh | sudo bash >/dev/null 2>&1;
    echo "Installer Rclone"
  fi
}
clear
sleep 3
#####
### Installer Mate Desktop
#####
_Install-Mate
sleep 2
#####
### MergerFs
_MERGERSF >/dev/null 2>&1;
sleep 3
#####
#####
### Install Filebot
#####
_Install-FileBot
sleep 3
#####
### Update fuse.conf  allow other
#####
echo "user_allow_other" >> /etc/fuse.conf
#####
###
#####
touch /etc/systemd/system/{rclonemount.service,mergerfs.service} >/dev/null 2>&1
sudo -u $USER touch /home/$USER/scripts/{rclone-upload.sh,slet.sh} >/dev/null 2>&1
sudo -u $USER touch /home/$USER/.config/rclone/rclone.conf >/dev/null 2>&1
sudo -u $USER chown $USER:$GROUP /home/$USER/{mnt/{move,gdrive,media},.config/rclone,scripts/logs} >/dev/null 2>&1
sudo -u $USER chown $USER:$GROUP /home/$USER/.config/rclone/rclone.conf >/dev/null 2>&1
sudo -u $USER chmod a+x /home/$USER/scripts/{rclone-upload.sh,slet.sh} >/dev/null 2>&1
#####
### PlexToken
#####
_TOKENPLEX
sleep 3

# Rclone Gdrive Config
echo "**********  Rclone Config Setup!"
echo "**********  Indtast Google Drive Client_id"
read -p 'Client_id: ' clientid
echo "**********  Indtast Google Drive Client_secret"
read -p 'client_secret: ' clientsecret
sudo -s rclone authorize drive
echo "*********   Indset Her!"
read -p 'Paste the following into your remote machine; ' token

#################################################################################################

## Rclone.config

cat >> /home/$USER/.config/rclone/rclone.conf <<EOF
[gdrive]
type = drive
client_id = $clientid
client_secret = $clientsecret
scope =
root_folder_id =
service_account_file =
token = $token
[gcrypt]
type = crypt
remote = gdrive:/encrypt
filename_encryption = standard
directory_name_encryption = true
EOF

## Rclone Crypt Password
echo "Rclone Crypt Password!"
echo "*********    Indtast Rclone crypt Password 1"
read -s -p "Password_1: " pass1
echo "*********    Indtast Rclone crypt Password_2"
read -s -p "Indtast Password 2: " pass2


sudo -s rclone config password gcrypt password $pass1
sudo -s rclone config password gcrypt password2 $pass2

## Lave Rclone Mount

#######################################################################################


cat >> /etc/systemd/system/rclonemount.service <<EOF
[Unit]
Description=RClone Service
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gcrypt: /home/$USER/mnt/gdrive \
--allow-other \
--dir-cache-time 72h \
--vfs-read-chunk-size 10M \
--vfs-read-chunk-size-limit 512M \
--buffer-size 1G \
--umask 002 \
--log-level INFO \
--log-file /home/$USER/scripts/logs/rclone-mount.txt
ExecStop=/bin/fusermount -uz /home/$USER/mnt/gdrive
Restart=on-abort
User=$USER
Group=$USER
[Install]
WantedBy=default.target
EOF

## Megerfs Mount

cat >> /etc/systemd/system/mergerfs.service <<EOF
[Unit]
Description=Megerfs Service
After=rclonemount.service
RequiresMountsFor=/home/$USER/mnt/gdrive
[Service]
Type=forking
User=$USER
Group=$USER
ExecStart=/usr/bin/mergerfs -o defaults,sync_read,allow_other,category.action=all,category.create=ff /home/$USER/mnt/move:/home/$USER/mnt/gdrive /home/$USER/mnt/media
ExecStop=/home/$USER/mnt/gdrive
Restart=on-abort
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3
[Install]
WantedBy=rclonemount.service
EOF

## Set UserName Rclone Upload

echo -e "#!/bin/bash\nLOGFILE=/home/$USER/scripts/logs/rclone-upload.log\nFROM=/home/$USER/mnt/move\nTO=gcrypt:/" >> /home/$USER/scripts/rclone-upload.sh

## Rclone Upload Scripts

cat >> /home/$USER/scripts/rclone-upload.sh << 'EOF'
if pidof -o %PPID -x "$0"; then
   exit 1
fi
# CHECK FOR FILES IN FROM FOLDER THAT ARE OLDER THAN 15 MINUTES
if find $FROM* -type f -mmin +15 | read
  then
  start=$(date +'%s')
  echo "$(date "+%d.%m.%Y %T") RCLONE UPLOAD STARTED" | tee -a $LOGFILE
  # MOVE FILES OLDER THAN 15 MINUTES
  rclone move "$FROM" "$TO" --transfers=20 --bwlimit 25M --checkers=20 --delete-after --min-age 15m --log-file=$LOGFILE
  echo "$(date "+%d.%m.%Y %T") RCLONE UPLOAD FINISHED IN $(($(date +'%s') - $start)) SECONDS" | tee -a $LOGFILE
fi
exit
EOF

########################################################################

##Slet Tomme Mapper


cat >> /home/$USER/scripts/slet.sh <<EOF
#!/bin/bash
# remove empty directories
find /home/$USER/mnt/move/movies* -empty -type d -delete 2>/dev/null
find /home/$USER/mnt/move/tv* -empty -type d -delete 2>/dev/null
find /home/$USER/mnt/move/Unsorted* -empty -type d -delete 2>/dev/null
find /home/$USER/mnt/move/Movies 4K* -empty -type d -delete 2>/dev/null
find /home/$USER/mnt/move/Tv 4K* -empty -type d -delete 2>/dev/null
find /home/$USER/mnt/move/.Trash-1000/* -empty -type d -delete 2>/dev/null
EOF

#######################################################################

## Set Crontab

cat >> /etc/crontab << EOF
* * * * * $USER /home/$USER/scripts/rclone-upload.sh
* * * * * $USER /home/$USER/scripts/slet.sh
EOF

#######################################################################
## Filebot Command til Qbittorrent
cat >> /home/$USER/scripts/FileBot-Commad <<EOF
filebot -script fn:amc --lang da --output "/home/$USER/mnt/media" --action copy --conflict auto -non-strict --log-file "/home/$USER/scripts/logs/filebot-amc.log" --def unsorted=y music=y artwork=n plex="localhost:${PLEXTOKEN}" "ut_dir=%F" "ut_kind=multi" "ut_title=%N" "ut_label=%L" --def movieFormat="{vf == /2160p/ ? 'Movies 4K' : vf =~ /1080p|720p/ ? 'movies' : 'movies'}/{Languages.toString().contains('da') || audioLanguages.toString().contains('da')? 'Dansk' : 'Engelsk'}/{n}/{n.space('.')}.{y}{'.'+source}.{vc}{'.'+lang}" seriesFormat="{vf == /2160p/ ? 'Tv 4K' : vf =~ /1080p|720p/ ? 'tv' : 'tv'}/{Languages.toString().contains('da') || audioLanguages.toString().contains('da')? 'Dansk' : 'Engelsk'}/{n}/{'Season '+s}/{n} - {s00e00} - {t}{'.'+lang}"
EOF
#####
### start rclone Mount
#####
systemctl daemon-reload
systemctl enable rclonemount.service
systemctl start rclonemount.service
#####
### Start mergerfs Mount
#####
systemctl enable mergerfs.service
systemctl start mergerfs.service
## Reboot
rm -rf /home/$USER/mergerfs >/dev/null 2>&1
rm -rf /home/$USER/install >/dev/null 2>&1
echo "så tager vi lige en Genstart"
sleep 4
echo "Efter Genstart | Log Ind Med NoMachine"
sleep 5
read -p "Tryk Enter For Og Genstarte"
sudo -s reboot
