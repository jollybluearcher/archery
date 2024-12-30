#!/usr/bin/env bash

clear   # Clear the TTY
set -e  # The script will not run if we CTRL + C, or in case of an error
set -u  # Treat unset variables as an error when substituting

. install.conf

arch-chroot /mnt /bin/bash << EOF
timedatectl set-ntp true
ln -sf /usr/share/zoneinfo/$continent_city /etc/localtime
hwclock --systohc
sed -i "s/#en_GB/en_GB/g; s/#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
locale-gen

sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  # Making pacman prettier
sed -i "s/#Color/Color/g" /etc/pacman.conf  # Add color to pacman
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 10/g" /etc/pacman.conf  # Parallel downloads
tee -a /etc/pacman.conf << END
[multilib]
Include = /etc/pacman.d/mirrorlist
END

pacman -S linux linux-firmware intel-ucode networkmanager efibootmgr btrfs-progs neovim zsh wpa_supplicant dosfstools e2fsprogs sudo tmux rsync openssh git htop openvpn networkmanager-openvpn fzf ruby python nodejs earlyoom thermald xorg-server xorg-xinput xf86-video-fbdev lib32-mesa libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau zram-generator mkinitcpio --noconfirm

echo -e "127.0.0.1\tlocalhost" >> /etc/hosts
echo -e "::1\t\tlocalhost" >> /etc/hosts
echo -e "127.0.1.1\t$hostname.localdomain\t$hostname" >> /etc/hosts

echo -e "KEYMAP=$keymap" > /etc/vconsole.conf
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo 'Defaults !tty_tickets' >> /etc/sudoers
sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf

tee -a /etc/modprobe.d/nobeep.conf << END
blacklist pcspkr
END

echo -e "$hostname" > /etc/hostname
useradd -m -g users -G wheel,games,power,optical,storage,scanner,lp,audio,video,input,adm,users -s /bin/zsh $username
echo -en "$root_password\n$root_password" | passwd
echo -en "$user_password\n$user_password" | passwd $username

sed -i "s/^# %wheel/%wheel/g" /etc/sudoers
tee -a /etc/sudoers << END
Defaults editor=/usr/bin/nvim
END

systemctl enable NetworkManager.service NetworkManager-wait-online.service fstrim.timer sshd.service earlyoom.service

journalctl --vacuum-size=100M --vacuum-time=2weeks

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

touch /etc/udev/rules.d/backlight.rules
tee -a /etc/udev/rules.d/backlight.rules << END
RUN+="/bin/chgrp video /sys/class/backlight/intel_backlight/brightness"
RUN+="/bin/chmod g+w /sys/class/backlight/intel_backlight/brightness"
END

touch /etc/udev/rules.d/81-backlight.rules
tee -a /etc/udev/rules.d/81-backlight.rules << END
SUBSYSTEM=="backlight", ACTION=="add", KERNEL=="intel_backlight", ATTR{brightness}="9000"
END

mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/100-systemd-boot.hook
tee -a /etc/pacman.d/hooks/100-systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
END

tee -a /etc/systemd/zram-generator.conf << END
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
END

sed -i "s/^HOOKS.*/HOOKS=(base systemd keyboard autodetect sd-vconsole modconf block sd-encrypt btrfs filesystems fsck)/g" /etc/mkinitcpio.conf
sed -i 's/^BINARIES.*/BINARIES=(btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P
bootctl --path=/boot/ install

mkdir -p /boot/loader/
tee -a /boot/loader/loader.conf << END
default arch.conf
console-mode max
editor no
END

mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options rd.luks.name=$(blkid -s UUID -o value $ROOT)=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 i915.enable_psr=0 nmi_watchdog=0 quiet rw
END
EOF

umount -R /mnt
