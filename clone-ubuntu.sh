#!/usr/bin/env bash
# Autor: Thiago Silva
# Contact: thiagos.dasilva@gmail.com
# URL: https://github.com/thiggy01/clone-ubuntu
# ============================================= #

## Make sure the script has the appropriate environmnet to run ##

# $TERM variable may be missing when called via desktop shortcut.
CurrentTERM=$(env | grep TERM)
if [ "$CurrentTERM" = "" ] ; then
    notify-send --urgency=critical \
        "$0 cannot be run from GUI without TERM environment variable."
    exit 1
fi

# Script must be run as root.
if [ "$(id -u)" -ne 0 ] ; then
    echo "Usage: sudo $0"
    exit 1
fi

# Create unqique temporary file names.

TmpUUIDList=$(mktemp /tmp/clone-ubuntu.XXXXX)
TmpWhiptailMenu=$(mktemp /tmp/clone-ubuntu.XXXXX)

## Create functions for repeated code ##

# Removes temporary files and umount clone partitions.
CleanUp () {
    [ -f "$TmpUUIDList" ] && rm -f "$TmpUUIDList"
    [ -f "$TmpWhiptailMenu" ] && rm -f "$TmpWhiptailMenu"
    if [ -d "$TargetRootMnt" ]; then
        umount "$TargetRootMnt" -l
        rm -d "$TargetRootMnt"
    fi
    if [ -d "$TargetHomeMnt" ]; then
	umount "$TargetHomeMnt" -l
	rm -d "$TargetHomeMnt"
    fi
}

# Gets UUIDs of source and clone target partitions in menu.
GetUUID () {
    UUID_col=0
    lsblk -o NAME,UUID > "$TmpUUIDList"
    while read -r UUID_Line; do
        # Establish UUID position on line
        if [ $UUID_col = 0 ] ; then
            UUID_col="${UUID_Line%%UUID*}"
            UUID_col="${#UUID_col}"
            NameLen=$(( UUID_col - 1 ))
            continue
        fi
        # Check if passed line name (/dev/sda1, /nvme01np8, etc) matches.
        if [ "${UUID_Line:0:$NameLen}" = "${Line:0:$NameLen}" ] ; then
            FoundUUID="${UUID_Line:UUID_col:999}"
            break
        fi
    done < "$TmpUUIDList"
}

# Verify if it's a valid ext4 filesystem umounted partition.
Validate () {
    if echo "${Line%% *}" | grep -qv '[0-9]'; then
	echo "Invalid partition selection."
	echo "Choose an umounted ext4 partition."
	read -p "Press <Enter> to continue"
	return 1
    fi
    if [ "${Line:FSTYPE_col:4}" != 'ext4' ] ; then
	echo "You can't clone to a(n) ${Line:FSTYPE_col:4} partition."
        echo "Only 'ext4' partitions can be cloning targets."
        read -p "Press <Enter> to continue"
	return 1
    fi
    if [ "${Line:MOUNTPOINT_col:4}" != '    ' ] ; then
        echo "A Mounted partition can not be a clone target."
        read -p "Press <Enter> to continue"
	return 1
    fi
}

## Create a menu which allow users to select target root and home partitions ##

# Generate menu list
lsblk -o NAME,FSTYPE,LABEL,SIZE,MOUNTPOINT > "$TmpWhiptailMenu"
# Initialize variables
i=0
SPACES='                                                                     '
Heading=true
AllPartsArr=()
# As long as there's a line to read, build whiptail menu tags and text into
# an array.
while read -r Line; do
    # Get heading text, file system and mount point positions.
    if [ "$Heading" = true ] ; then
        Heading=false
        MenuText="$Line"
        FSTYPE_col="${Line%%FSTYPE*}"
        FSTYPE_col="${#FSTYPE_col}"
        MOUNTPOINT_col="${Line%%MOUNTPOINT*}"
        MOUNTPOINT_col="${#MOUNTPOINT_col}"
        continue
    fi
    # Adjust line position and length
    Line="$Line$SPACES"
    Line=${Line:0:74}
    # Get Root source UUID and device.
    if [ "${Line:MOUNTPOINT_col:4}" = "/   " ] ; then
        GetUUID
        SourceRootUUID=$FoundUUID
        # Build "/dev/Xxxxx" FS name from "├─Xxxxx" lsblk line
        SourceRootDev="${Line%% *}"
        SourceRootDev=/dev/"${SourceRootDev:2:999}"
    fi
    # Get Home source UUID and device.
    if [ "${Line:MOUNTPOINT_col:5}" = "/home" ] ; then
        GetUUID
        SourceHomeUUID=$FoundUUID
        # Build "/dev/Xxxxx" FS name from "├─Xxxxx" lsblk line
        SourceHomeDev="${Line%% *}"
        SourceHomeDev=/dev/"${SourceHomeDev:2:999}"
    fi
    # Add whiptail menu tags and text.
    AllPartsArr+=("$i" "$Line")
    (( i++ ))
# Get menu list from temporary file.
done < "$TmpWhiptailMenu"
# Display whiptail menu in while loop until no errors or escape is pressed or
# a valid partition is selected.
    # Call whiptail box to paint instruction info and message boxes.
    TERM=ansi whiptail --infobox "Starting clone-ubuntu script ..." 7 36
    sleep 10; clear
    whiptail --title "Booting and Partitioning" \
--msgbox "Your boot loader must be grub2 and you'll have to remove all changes \
made by grub-customizer if installed.

You'll need to create a BIOS boot partition of at least 1MiB \
to boot from a BIOS/GPT layout.

You'll need to create an EFI system partition of at least 100MiB to boot from \
an UEFI/MBR or an UEFI/GPT layout.

These booting partitions need to be created before your system partitions for \
GRUB to work properly.

You must create empty ext4 partitions large enough to hold at least the size of \
your root and home (if there is one) data.

For information about how to create them, visit: \
https://wiki.archlinux.org/index.php/Partitioning
" 23 76
    whiptail --title "Prerequisites and Warnings" \
	--msgbox "The script must be ran in a terminal running bash shell and \
whiptail package has to be installed.

You must be cloning from inside your mounted root system and home partition to \
another disk.

Your target clone partitions must not be mounted and have to be an ext4 file \
system.

When you are recloning, any new data on the previous clone partition will be \
deleted.

Don't use your computer while it's being cloned because you may end up with \
inconsistent data between your cloned source and clone target.

IF YOU DON'T FOLLOW THE INSTRUCTIONS GIVEN ABOVE, THIS SCRIPT WILL DISPLAY A \
WARNING MESSAGE AND ABORT THE CLONING PROCESS." 23 76

    whiptail --title "Menu navegation and selection instructions" \
	--msgbox "Press arrow up or down to go up or down through the menu.
Press arrow left or right to toggle between Select and Exit options.
Press <Enter> to choose the desired clone partition." 10 72
while true; do
    # Call whiptail to paint partitions menu.
    Choice=$(whiptail \
        --title "Select the target root / partition" \
        --ok-button "Select" \
        --cancel-button "Exit" \
        --notags \
        --menu "$MenuText" 24 80 16 \
        "${AllPartsArr[@]}" \
        2>&1 >/dev/tty)
    clear
    # If no choice was made, clean and exit.
    if [ "$Choice" = "" ]; then
        CleanUp
        exit 0;
    fi
    # Get user selection.
    ArrIdx=$(( $Choice * 2 + 1))
    Line="${AllPartsArr[$ArrIdx]}"
    # Get UUID from source partition.
    GetUUID
    # Build target device name from line.
    TargetRootUUID=$FoundUUID
    TargetRootDev="${Line%% *}"
    TargetRootDev=/dev/"${TargetRootDev:2:999}"
    # validate selection.
    Validate
    [ $? -eq 1 ] && continue
    # Verify if the script is cloning to another disk.
    # Changed regex to fix a bug with NVMe disks thanks to @alexlemaire from Github.
    SourceDisk=$(echo "$SourceRootDev" | sed 's/p\?[0-9]\+$//')
    TargetDisk=$(echo "$TargetRootDev" | sed 's/p\?[0-9]\+$//')
    if [ "$SourceDisk" != "$TargetDisk" ]; then
	# Check if Bios boot partition is present.
	if fdisk -l "$TargetDisk" | grep -q 'BIOS'; then
	    whiptail --msgbox "BIOS boot partition detected.
Press <Enter> to continue." 8 34
	    clear
	# Check if EFI system partition is present.
	elif fdisk -l "$TargetDisk" | grep -q 'EFI'; then
	    whiptail --msgbox "EFI system partition detected.
Press <Enter> to continue." 8 34
	    clear
	    # Get the new EFI system partition device.
	    NewEfiDev="$(fdisk -l "$TargetDisk" | grep 'EFI' | sed 's/\s.*//')"
	    # Check what kernel architecture is being used.
	    case $(uname -m) in i?86) GrubTarget='i386-efi' ;;\
		x86_64) GrubTarget='x86_64-efi' ;; esac
	# If disk has a MBR partition table, don't do anything.
	elif fdisk -l "$TargetDisk" | grep -q 'dos'; then
	    whiptail --msgbox "A MBR partition table was detected.
There's no need to create any boot partition.
Press <Enter> to continue." 9 62
	else
	    # If there's no boot partition, exit.
	    echo "A BIOS boot partition is required to boot from a BIOS/GPT layout."
	    echo "An EFI system partition is required to boot from an UEFI/GPT layout."
	    echo "No BIOS boot or EFI system partition were found."
	    echo "Abortig cloning process."
	    read -p "Press <Enter> to exit."
	    CleanUp
	    exit 1
	fi
    else
	echo "This script won't clone to the source disk."
	echo "Please, choose anohter target disk."
	read -p "Press <Enter> to exit."
	CleanUp
	exit 1
    fi
    # If there is a /home partition, clone it.
    if lsblk | grep -w "/home"; then
	whiptail --msgbox "/home partition detected.
Press <Enter> to continue" 7 29
	clear
	Choice=$(whiptail \
	  --title "Select the target /home partition" \
	  --ok-button "Select" \
	  --cancel-button "Exit" \
	  --notags \
	  --menu "$MenuText" 24 80 16 \
	  "${AllPartsArr[@]}" \
	  2>&1 >/dev/tty)
	clear
	if [[ $Choice = "" ]]; then
	   CleanUp
	   exit 0;
	fi
	ArrIdx=$(( $Choice * 2 + 1 ))
	Line="${AllPartsArr[$ArrIdx]}"
	#Get UUID of source partition and build target device name from menu line.
	GetUUID
	TargetHomeUUID=$FoundUUID
	TargetHomeDev="${Line%% *}"
	TargetHomeDev=/dev/"${TargetHomeDev:2:999}"
	Validate
	[ "$?" = 1 ] && continue
    fi
    break
done

## Get confirmation about root and clone partitions. ##

TargetRootMnt='/mnt/root'
echo "========================================================================"
echo "Mounting root partition $TargetRootDev as $TargetRootMnt"
echo
mkdir -p "$TargetRootMnt"
mount -t ext4 "$TargetRootDev" "$TargetRootMnt"
if [ -z "$TargetHomeDev" ]; then
# Ask user if he wants to exclude specific folders from the cloning process.
    echo
    echo "The folders /dev /proc /sys /tmp /run /mnt /media /lost+found will "
    echo "be excluded from the cloning process because they will be recreated"
    echo "on your cloned environment when you boot it for the first time."
    echo "Do you want to exclude any other folder?"
else
    echo "The folders /dev /proc /sys /tmp /run /mnt /media /lost+found will "
    echo "be excluded from the cloning process because they will be recreated"
    echo "on your cloned environment when you boot it for the first time."
    echo "Do you want to exclude any other folder?"
    echo "*****************************Warning************************************"
    echo "Don't try to exclude any directory from your separate /home partition"
    echo "because they will not be excluded, since /home partition will be cloned"
    echo "later, after the / partition cloning process."
    echo "************************************************************************"
fi
read -p "Type Y or y if yes. Other keys if no: " -n 1
echo
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "------------------------------------------------------------------------"
    echo "Insert the full path to the folder and press <Enter> to include."
    echo "You can insert as many folders as you want and everything inside it will"
    echo "be excluded from the cloning process."
    echo "Press <Ctrl> + D to finish adding directories."
    while IFS= read UserFolder; do
	Excludes+=( --exclude="$UserFolder" )
	(( ExcludesSize+=$(du -s "$UserFolder" | cut -f 1) )) 2> /dev/null
	if [ "$?" -eq 1 ]; then
	    echo "Folder not found. Please, submit a valid path."
	fi
    done
    # Get the space used by source partition without excluded folders and size of target
    # partition.
    UsedSpaceSrc=$(( $(df --output=used "$SourceRootDev" | sed -n 2p) - "$ExcludesSize" )) \
    SizeSpaceTgt=$(df --output=size "$TargetRootDev" | sed -n 2p)
else
    # Get the full space used by source partition and size of target partition.
    UsedSpaceSrc=$(df --output=used "$SourceRootDev" | sed -n 2p)
    SizeSpaceTgt=$(df --output=size "$TargetRootDev" | sed -n 2p)
fi
if [ "$UsedSpaceSrc" -gt "$SizeSpaceTgt" ]; then
    clear
    echo "Space used in source root partition is greater than space in selected target"
    echo "Aborting cloning process."
    read -p "Press <Enter> to exit."
    CleanUp
    exit 1
fi
# Test if target partition is not an empty partition.
EmptyPart='true'
LineCount=$(ls "$TargetRootMnt" | wc -l)
if (( LineCount > 1 )) ; then
    if [ -f "$TargetRootMnt"/etc/lsb-release ] ; then
	echo
	echo "Selected partition has a(n) $(lsb_release -d | sed 's/Description:\s*//g') \
operating system installation."
	echo "Are you sure you want to overwrite your target $TargetRootDev root partition?"
	echo
	read -p "Press Y (or y) to proceed. Any other key to exit: " -n 1
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]] ; then
	    CleanUp
	    exit 0
	else
	    EmptyPart='false'
	fi
    else
        # Don't select partitions other than the system root partition.
	clear
        echo "Selected partition is not an empty root partition."
	echo "Aborting cloning process."
	read -p "Press <Enter> to exit"
        CleanUp
        exit 1
    fi
fi
# Get confirmation to proceed with the root cloning process.
if [ "$EmptyPart" == 'true' ]; then
    echo
    echo "========================================================================"
    echo "Are you sure you want to clone $SourceRootDev to $TargetRootDev?"
    read -p "Press Y or y to proceed. Any other key to exit: " -n 1
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
	CleanUp
	exit 0
    fi
fi

## Copy root partition to target partition and update fstab and grub menu. ##

# If there's a /home partition, don't clone it.
if [ -n "$TargetHomeDev" ]; then
    SECONDS=0
    echo
    echo "========================================================================"
    echo "Using rsync to clone / to $TargetRootDev mounted as $TargetRootMnt"
    rsync -axhAX --info=progress2 --info=name0 --delete --inplace --stats \
        /* "$TargetRootMnt" \
	--exclude={/home/*,/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} \
	"${Excludes[@]}"
    echo
    echo "Time to clone files: $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
# If there isn't a /home partition, don't exclude /home directory from the cloning process.
else
    SECONDS=0
    echo
    echo "========================================================================"
    echo "Using rsync to clone / to $TargetRootDev mounted as $TargetRootMnt"
    rsync -axhAX --info=progress2 --info=name0 --delete --inplace --stats \
	/* "$TargetRootMnt" \
	--exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} \
	"${Excludes[@]}"
    echo
    echo "Time to clone files: $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
fi
# Update /etc/fstab and /boot/grub/grub.cfg on target partition with clone's UUID
echo
echo "========================================================================"
echo "Updating $TargetRootMnt/etc/fstab and $TargetRootMnt/boot/grub/grub.cfg files."
echo
echo "from UUID: $SourceRootUUID"
echo "  to UUID: $TargetRootUUID"
sed -i "s/$SourceRootUUID/$TargetRootUUID/g" "$TargetRootMnt"/etc/fstab
sed -i "s/$SourceRootUUID/$TargetRootUUID/g" "$TargetRootMnt"/boot/grub/grub.cfg
echo
echo "========================================================================"
# If cloning to another disk, check if there is a boot partition and install and
# update grub accordingly.
echo "Changing root directory from / to $TargetRootMnt ..."
for i in /dev /sys /proc /run; do mount --bind "$i" "$TargetRootMnt$i"; done
if [ -n "$NewEfiDev" ]; then
    if [ ! -d "$TargetRootMnt"/boot/efi ]; then
	echo "Creating EFI system partition directory ..."
	mkdir "$TargetRootMnt"/boot/efi
    fi
    echo "Mounting EFI system partition ..."
    mount "$NewEfiDev" "$TargetRootMnt"/boot/efi
    if grep -q 'efi' "$TargetRootMnt"/etc/fstab; then
	echo "Removing EFI entry from fstab file ..."
	sed -i '/efi/d' "$TargetRootMnt"/etc/fstab
    fi
    echo "Checking if an EFI enabled grub is installed ..."
    chroot "$TargetRootMnt" dpkg -S 'grub-efi' >& /dev/null; \
	[ "$?" -eq 1 ] && GrubEfi='false'

    if [ "$GrubEfi" = 'false' ]; then
	echo "Installing EFI enabled GRUB package ..."
	chroot "$TargetRootMnt" apt-get install -y grub-efi >& /dev/null
	echo "Installing GRUB boatloader on $TargetDisk disk ..."
	chroot "$TargetRootMnt" grub-install --target="$GrubTarget" \
	    "$TargetDisk"
	echo "Calling 'update-grub' to create a new boot menu ..."
	chroot "$TargetRootMnt" update-grub
	echo "Umounting EFI System Partition ..."
	umount "$NewEfiDev"
    else
	echo "Installing GRUB boatloader on $TargetDisk disk ..."
	chroot "$TargetRootMnt" grub-install --target="$GrubTarget" \
	    "$TargetDisk"
	echo "Calling 'update-grub' to create a new boot menu ..."
	chroot "$TargetRootMnt" update-grub
	echo "Umounting EFI System Partition ..."
	umount "$NewEfiDev"
    fi
else
    echo "Installing GRUB boatloader on $TargetDisk disk ..."
    chroot "$TargetRootMnt" grub-install "$TargetDisk"
    echo "Calling 'update-grub' to create a new boot menu ..."
    chroot "$TargetRootMnt" update-grub
fi


## Get confirmation about home and clone partitions. ##

if [ -n "$TargetHomeDev" ]; then
    TargetHomeMnt='/mnt/home'
    echo
    echo "========================================================================="
    echo "Mounting home partition $TargetHomeDev as $TargetHomeMnt"
    echo
    mkdir "$TargetHomeMnt"
    mount -t ext4 "$TargetHomeDev" "$TargetHomeMnt"
    # Ask user if he wants to exclude any folder from the cloning process.
    echo "Do you want to exclude any folder from your /home partition?"
    read -p "Type Y or y if yes. Other keys if no: " -n 1
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
	echo "-------------------------------------------------------------------------"
	echo "Insert the full path to the folder and press <Enter> to include."
	echo "You can insert as many folders as you want and everything inside it will"
	echo "be excluded from the cloning process."
	echo "Press <Ctrl> + D to finish adding directories"
	while IFS= read UserFolder; do
	    Excludes+=( --exclude="$UserFolder" )
	    (( ExcludesSize+=$(du -s "$UserFolder" | cut -f 1) )) 2> /dev/null
	    if [ "$?" -eq 1 ]; then
		echo "Folder not found."
		echo "Submit a valid path."
	    fi
	done
	# Get the space used by source partition without excluded folders and size of target
	# partition.
	UsedSpaceSrc=$(( "$(df --output=used "$SourceHomeDev" | sed -n 2p)" - "$ExcludesSize" ))
	SizeSpaceTgt=$(df --output=size "$TargetHomeDev" | sed -n 2p)
    else
	# Get the full space used by source partition and size of target partition.
	UsedSpaceSrc=$(df --output=used "$SourceHomeDev" | sed -n 2p)
	SizeSpaceTgt=$(df --output=size "$TargetHomeDev" | sed -n 2p)
    fi
    if [ "$UsedSpaceSrc" -gt "$SizeSpaceTgt" ]; then
	clear
	echo "Space used in source /home partition is greater than space in selected target"
	echo "Aborting cloning process."
	read -p "Press <Enter> to exit"
	echo
	CleanUp
	exit 1
    fi
    # Test if target home partition is empty.
    EmptyPart='true'
    LineCnt=$(ls "$TargetHomeMnt" | wc -l)
    if (( LineCnt > 1 )); then
	# If it's not empty and it's a root system, abort.
	if [ -f "$TargetHomeMnt"/etc/lsb-release ] ; then
	    clear
	    echo "Selected partition is a root partition. Aborting."
	    CleanUp
	    exit 1
	else
	    echo
	    echo "Your target /home partition already has some data in it"
	    echo "You may lose some data if they're not in your source partition"
	    echo "Are you sure you want to overwrite your target $TargetHomeDev /home partition?"
	    echo
	    read -p "Type Y (or y) to proceed. Any other key to exit: " -n 1
	    echo
	    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
		CleanUp
		exit 0
	    else
		EmptyPart='false'
	    fi
	fi
    fi
    if [ "$EmptyPart" == 'true' ]; then
	echo
	echo "========================================================================="
	echo "Are you sure you want to clone $SourceHomeDev to $TargetHomeDev?"
	echo
	# Confirmation to proceed.
	read -p "Type Y (or y) to proceed. Any other key to exit: " -n 1
	echo
	if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
	    CleanUp
	    exit 0
	fi
    fi

    ## Copy home partition to target partition. ##

    SECONDS=0
    echo
    echo "========================================================================="
    echo "Using rsync to clone /home to $TargetHomeDev mounted as $TargetHomeMnt"
    rsync -axhAX --info=progress2 --info=name0 --delete --inplace --stats   \
	/home/* "$TargetHomeMnt" "${Excludes[@]/\/home/}"
    echo
    echo "Time to clone files: $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
    # Update /etc/fstab on clone partition with clone's UUID
    echo
    echo "========================================================================="
    echo "Updating $TargetRootMnt/etc/fstab file"
    echo "from UUID: $SourceHomeUUID"
    echo "  to UUID: $TargetHomeUUID"
    sed -i "s/$SourceHomeUUID/$TargetHomeUUID/g" "$TargetRootMnt"/etc/fstab
    # Display Unmount home clone partition message.
    echo
    echo "========================================================================="
    echo "Unmounting $TargetHomeDev as $TargetHomeMnt"
fi

## Unmount root partition, remove temporaty files and give final instructions ##
## before exit the scritp sucessfully. ##

echo
echo "========================================================================="
echo "Unmounting $TargetRootDev as $TargetRootMnt"
echo
echo "========================================================================="
echo "Cloning process finished"
echo
echo "You can now change your boot device on your BIOS/UEFI firmware to boot from"
echo "your newly cloned Ubuntu system."
echo
echo "Your clone Ubuntu system will be the first meny entry in the Grub menu."
echo
echo "If it boots and login normally, you can safely remove, format or change"
echo "your source disk to whatever you like."
echo
echo "If you use grub-customizer or has custom menu entries, you can also"
echo "customize your grub menu the way you like after that."
echo
CleanUp
exit 0
