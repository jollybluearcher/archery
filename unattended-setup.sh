#!/usr/bin/env bash

clear   # Clear the TTY
set -e  # The script will not run if we CTRL + C, or in case of an error
set -u  # Treat unset variables as an error when substituting

read -s -p "Enter encryption passphrase: " ENC_PASSPHRASE

if [ "$PRIMARY" == nvme0n1 ] ; then
    bootpt="p1"
    rootpt="p2"
else
    bootpt=1
    rootpt=2
fi

DRIVE=/dev/$PRIMARY
BOOT=$DRIVE$bootpt
ROOT=$DRIVE$rootpt

if [ -z $SECONDARY ] ; then
    HOMEDRIVE=/dev/$SECONDARY
    if [ "$SECONDARY" == nvme1n1 ] ; then
        homept="p1"
    else
        homept=1
    fi
    HOME=$HOMEDRIVE$homept
fi

timedatectl set-ntp true  # Synchronize motherboard clock

primaryDriveSetup () {
  sgdisk --zap-all $DRIVE  # Delete tables
  sgdisk --clear \
    --new=1:0:+600MiB --typecode=1:ef00 --change-name=1:EFI\
    --new=2:0:0 --typecode=2:8300 --change-name=1:SYSTEM\
    $DRIVE
  mkfs.fat -F32 -n EFI $BOOT

  mkdir -p -m0700 /run/cryptsetup  # Change permission to root only
  echo $ENC_PASSPHRASE | cryptsetup luksFormat --type luks2 $ROOT
  echo $ENC_PASSPHRASE | cryptsetup luksOpen $ROOT cryptroot  # Open the mapper

  mkfs.btrfs /dev/mapper/cryptroot  # Format the encrypted partition
}

secondaryDriveSetup () {
  sgdisk --zap-all $HOMEDRIVE  # Delete tables
  sgdisk --clear \
    --new=1:0:0 --typecode=1:8300 --change-name=1:HOME\
    $HOMEDRIVE

  echo $ENC_PASSPHRASE | cryptsetup luksFormat --type luks2 $HOME
  echo $ENC_PASSPHRASE | cryptsetup luksOpen $HOME crypthome  # Open the mapper

  mkfs.ext4 /dev/mapper/crypthome  # Format the encrypted partition

}

singleDriveSetup () {
  primaryDriveSetup

  btrfs su cr /mnt/@
  btrfs su cr /mnt/@home
  btrfs su cr /mnt/@tmp
  btrfs su cr /mnt/@snapshots
  btrfs su cr /mnt/@var_cache
  btrfs su cr /mnt/@var_log

  umount /mnt

  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{boot,home,var,.snapshots,tmp,swapspace} # Create directories for their respective subvolumes
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
  mkdir /mnt/var/{log,cache} # Create directories for their respective var subvolumes
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@var_cache /dev/mapper/cryptroot /mnt/var/cache
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
  mount $BOOT /mnt/boot
}

dualDriveSetup () {
  primaryDriveSetup
  secondaryDriveSetup

  btrfs su cr /mnt/@
  btrfs su cr /mnt/@tmp
  btrfs su cr /mnt/@snapshots
  btrfs su cr /mnt/@var_cache
  btrfs su cr /mnt/@var_log

  umount /mnt

  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{boot,var,.snapshots,tmp,swapspace} # Create directories for their respective subvolumes
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
  mkdir /mnt/var/{log,cache} # Create directories for their respective var subvolumes
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@var_cache /dev/mapper/cryptroot /mnt/var/cache
  mount -o noatime,compress-force=zstd:1,ssd,space_cache=v2,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
  mount $BOOT /mnt/boot

  mkdir -p /mnt/home
  mount /dev/mapper/crypthome /mnt/home
}

pacmanSetup () {
  sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  # Making pacman prettier
  sed -i "s/#Color/Color/g" /etc/pacman.conf  # Add color to pacman
  sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 10/g" /etc/pacman.conf  # Parallel downloads
  tee -a /etc/pacman.conf << END
[multilib]
Include = /etc/pacman.d/mirrorlist
END

  pacman -Syy
  pacman -S archlinux-keyring --noconfirm
  pacstrap /mnt base base-devel
}

while getopts "p:s:e:" option; do
  case $option in
    p) # Primary drive
    PRIMARY=$OPTARG
    ;;
    s) # Secondary drive
    SECONDARY=$OPTARG
    ;;
    e) # encryption passphrase
    ENC_PASSPHRASE=$OPTARG
    ;;
  esac
done

shift "$(( OPTIND - 1 ))"

if [ -z "$ENC_PASSPHRASE" ] || [ -z "$PRIMARY" ]; then
        echo 'Missing -p or -e, script requires a primary drive and encryption passphrase' >&2
        exit 1
fi

if [ -z $SECONDARY ] ; then
  singleDriveSetup
else
  dualDriveSetup
fi

pacmanSetup
genfstab -U /mnt >> /mnt/etc/fstab  # Generate the entries for fstab