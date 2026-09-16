# WARNING: disko wipes this disk. /docker and /data live on it today.
{
  disko.devices.disk.main = {
    type = "disk";
    # A by-id path stops a USB disk from taking the place of /dev/sda.
    device = "/dev/disk/by-id/ata-APPLE_SSD_SM0512F-replace-me";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
