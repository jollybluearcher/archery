#!/usr/bin/env bash

clear   # Clear the TTY
set -e  # The script will not run if we CTRL + C, or in case of an error
set -u  # Treat unset variables as an error when substituting

. install.conf

read -s -p "Enter userpass: " USER_PASSWORD
read -s -p "Enter rootpass: " ROOT_PASSWORD

arch-chroot /mnt /bin/bash << EOF
timedatectl set-ntp true
ln -sf /usr/share/zoneinfo/$LOCATION /etc/localtime
hwclock --systohc
sed -i "s/#en_GB/en_GB/g; s/#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
locale-gen

pacman -S linux linux-firmware amd-ucode networkmanager efibootmgr grub btrfs-progs neovim zsh wpa_supplicant dosfstools e2fsprogs sudo tmux rsync openssh git htop openvpn networkmanager-openvpn fzf ruby python nodejs earlyoom thermald xorg-server xorg-xinput xf86-video-fbdev xf86-video-amdgpu lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau zram-generator mkinitcpio --noconfirm

echo -e "127.0.0.1\tlocalhost" >> /etc/hosts
echo -e "::1\t\tlocalhost" >> /etc/hosts
echo -e "127.0.1.1\t$HOSTNAME.localdomain\t$HOSTNAME" >> /etc/hosts

echo -e "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults !tty_tickets" >> /etc/sudoers

sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf

tee -a /etc/modprobe.d/nobeep.conf << END
blacklist pcspkr
END

tee -a /etc/modprobe.d/amdgpu.conf << END
options amdgpu si_support=1
options amdgpu cik_support=1
END

tee -a /etc/modprobe.d/radeon.conf << END
options radeon si_support=0
options radeon cik_support=0
END

echo -e "$HOSTNAME" > /etc/hostname
useradd -m -g users -G wheel,games,power,optical,storage,scanner,lp,audio,video,input,adm,users -s /bin/zsh $USERNAME
echo -en "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd
echo -en "$USER_PASSWORD\n$USER_PASSWORD" | passwd $USERNAME

sed -i "s/^# %wheel/%wheel/g" /etc/sudoers
tee -a /etc/sudoers << END
Defaults editor=/usr/bin/nvim
END

systemctl enable NetworkManager.service NetworkManager-wait-online.service fstrim.timer sshd.service earlyoom.service thermald.service

tee -a /etc/pacman.conf << END

[multilib]
Include = /etc/pacman.d/mirrorlist
END

journalctl --vacuum-size=100M --vacuum-time=2weeks

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

mkdir -p /etc/X11/xorg.conf.d && tee <<'END' /etc/X11/xorg.conf.d/90-touchpad.conf 1> /dev/null
Section "InputClass"
        Identifier "touchpad"
        MatchIsTouchpad "on"
        Driver "libinput"
        Option "Tapping" "on"
EndSection
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

sed -i 's/^MODULES.*/MODULES=(amdgpu radeon)/g' /etc/mkinitcpio.conf
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
initrd /amd-ucode.img
initrd /initramfs-linux.img
options rd.luks.name=$(blkid -s UUID -o value $ROOT)=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard nmi_watchdog=0 loglevel=0 systemd.show_status=0 rd,udev.log_priority=0 mitigations=auto quiet rw
END
EOF

umount -R /mnt
