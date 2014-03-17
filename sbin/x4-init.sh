#!/system/bin/sh

# define basic kernel configuration
# *********************************************************

# Kernel type
	# KERNEL="SAM1"		# Samsung old bootanimation / zram concept
	# KERNEL="SAM2"		# Samsung new bootanimation / zram concept
	KERNEL="CM"		# Cyanogenmod+Omni

# path to internal sd memory
	# SD_PATH="/data/media"		# JB 4.1
	SD_PATH="/data/media/0"		# JB 4.2, 4.3, 4.4

# block devices
	SYSTEM_DEVICE="/dev/block/mmcblk0p9"
	CACHE_DEVICE="/dev/block/mmcblk0p8"
	DATA_DEVICE="/dev/block/mmcblk0p12"

# *********************************************************


# define file paths
X4_DATA_PATH="$SD_PATH/x4-kernel-data"
X4_LOGFILE="$BOEFFLA_DATA_PATH/kernel.log"
X4_STARTCONFIG="/data/.x4/startconfig"
X4_STARTCONFIG_DONE="/data/.x4/startconfig_done"
INITD_ENABLER="/data/.x4/enable-initd"


# If not yet exists, create a boeffla-kernel-data folder on sdcard 
# which is used for many purposes (set permissions and owners correctly)
	if [ ! -d "$X4_DATA_PATH" ] ; then
		/system/xbin/busybox mkdir $X4_DATA_PATH
		/system/xbin/busybox chmod 775 $X4_DATA_PATH
		/system/xbin/busybox chown 1023:1023 $X4_DATA_PATH
	fi

# maintain log file history
	rm $X4_LOGFILE.3
	mv $X4_LOGFILE.2 $BOEFFLA_LOGFILE.3
	mv $X4_LOGFILE.1 $BOEFFLA_LOGFILE.2
	mv $X4_LOGFILE $BOEFFLA_LOGFILE.1

# Initialize the log file (chmod to make it readable also via /sdcard link)
	echo $(date) X4-Kernel initialisation started > $X4_LOGFILE
	/system/xbin/busybox chmod 666 $X4_LOGFILE
	/system/xbin/busybox cat /proc/version >> $X4_LOGFILE
	echo "=========================" >> $X4_LOGFILE
	/system/xbin/busybox grep ro.build.version /system/build.prop >> $X4_LOGFILE
	echo "=========================" >> $X4_LOGFILE

# If rom comes without mount command in /system/bin folder, create busybox symlinks for mount/umount
	if [ ! -f /system/bin/mount ]; then
		/system/xbin/busybox mount -o remount,rw /
		/system/xbin/busybox ln /sbin/busybox /sbin/mount
		/system/xbin/busybox ln /sbin/busybox /sbin/umount
		/system/xbin/busybox mount -o remount,ro /
		echo $(date) "Rom does not come with mount command, symlinks created" > $X4_LOGFILE
	fi
		
# Correct /sbin and /res directory and file permissions
	mount -o remount,rw /

	# change permissions of /sbin folder and scripts in /res/bc
	/system/xbin/busybox chmod -R 755 /sbin
	/system/xbin/busybox chmod 755 /res/bc/*

	/system/xbin/busybox sync
	mount -o remount,ro /

# remove any obsolete X4-Config V2 startconfig done file
/system/xbin/busybox rm -f $X4_STARTCONFIG_DONE

# Set the options which change the stock kernel defaults
# to X4-Kernel defaults

	echo $(date) Applying X4-Kernel default settings >> $X4_LOGFILE

	# Ext4 tweaks default to on
	sync
	mount -o remount,commit=20,noatime $CACHE_DEVICE /cache
	sync
	mount -o remount,commit=20,noatime $DATA_DEVICE /data
	sync
	echo $(date) Ext4 tweaks applied >> $X4_LOGFILE

	# Sdcard buffer tweaks default to 256 kb
	echo 256 > /sys/block/mmcblk0/bdi/read_ahead_kb
	echo $(date) "SDcard buffer tweaks (256 kb) applied for internal sd memory" >> $X4_LOGFILE
	echo 256 > /sys/block/mmcblk1/bdi/read_ahead_kb
	echo $(date) "SDcard buffer tweaks (256 kb) applied for external sd memory" >> $X4_LOGFILE

	# AC charging rate defaults defaults to 1100 mA
	echo "1100" > /sys/kernel/charge_levels/charge_level_ac
	echo $(date) "AC charge rate set to 1100 mA" >> $X4_LOGFILE

# init.d support, only if enabled in settings or file in data folder
	if [ "CM" != "$KERNEL" ] || [ -f $INITD_ENABLER ] ; then
		echo $(date) Execute init.d scripts start >> $X4_LOGFILE
		if cd /system/etc/init.d >/dev/null 2>&1 ; then
			for file in * ; do
				if ! cat "$file" >/dev/null 2>&1 ; then continue ; fi
				echo $(date) init.d file $file started >> $X4_LOGFILE
				/system/bin/sh "$file"
				echo $(date) init.d file $file executed >> $X4_LOGFILE
			done
		fi
		echo $(date) Finished executing init.d scripts >> $X4_LOGFILE
	else
		echo $(date) init.d script handling by kernel disabled >> $X4_LOGFILE
	fi

	echo $(date) Rom boot trigger detected, waiting a few more seconds... >> $X4_LOGFILE
	/system/xbin/busybox sleep 10

# Interaction with X4-Config app V2
	# save original stock values for selected parameters
	cat /sys/devices/system/cpu/cpu0/cpufreq/UV_mV_table > /dev/bk_orig_cpu_voltage
	cat /sys/class/misc/gpu_clock_control/gpu_control > /dev/bk_orig_gpu_clock
	cat /sys/class/misc/gpu_voltage_control/gpu_control > /dev/bk_orig_gpu_voltage
	cat /sys/kernel/charge_levels/charge_level_ac > /dev/bk_orig_charge_level_ac
	cat /sys/kernel/charge_levels/charge_level_usb > /dev/bk_orig_charge_level_usb
	cat /sys/kernel/charge_levels/charge_level_wireless > /dev/bk_orig_charge_level_wireless
	cat /sys/module/lowmemorykiller/parameters/minfree > /dev/bk_orig_minfree
	/system/xbin/busybox lsmod > /dev/bk_orig_modules

	# if there is a startconfig placed by X4-Config V2 app, execute it
	if [ -f $X4_STARTCONFIG ]; then
		echo $(date) "Startup configuration found:"  >> $X4_LOGFILE
		cat $X4_STARTCONFIG >> $BOEFFLA_LOGFILE
		. $X4_STARTCONFIG
		echo $(date) Startup configuration applied  >> $X4_LOGFILE
	fi
	
# Turn off debugging for certain modules
	echo 0 > /sys/module/ump/parameters/ump_debug_level
	echo 0 > /sys/module/mali/parameters/mali_debug_level
	echo 0 > /sys/module/kernel/parameters/initcall_debug
	echo 0 > /sys/module/lowmemorykiller/parameters/debug_level
	echo 0 > /sys/module/earlysuspend/parameters/debug_mask
	echo 0 > /sys/module/alarm/parameters/debug_mask
	echo 0 > /sys/module/alarm_dev/parameters/debug_mask
	echo 0 > /sys/module/binder/parameters/debug_mask
	echo 0 > /sys/module/xt_qtaguid/parameters/debug_mask

# EFS backup
	EFS_BACKUP_INT="$X4_DATA_PATH/efs.tar.gz"
	EFS_BACKUP_EXT="/storage/extSdCard/efs.tar.gz"

	if [ ! -f $EFS_BACKUP_INT ]; then

		cd /efs
		/system/xbin/busybox tar cvz -f $EFS_BACKUP_INT .
		/system/xbin/busybox chmod 666 $EFS_BACKUP_INT

		/system/xbin/busybox cp $EFS_BACKUP_INT $EFS_BACKUP_EXT
		
		echo $(date) EFS Backup: Not found, now created one >> $X4_LOGFILE
	fi

# Finished
	echo $(date) X4-Kernel initialisation completed >> $X4_LOGFILE
