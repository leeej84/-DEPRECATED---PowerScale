# PowerScale
Citrix currently have a product called SmartScale, this product is being put out to pasture at the end of May.

The idea of PowerScale is to provide a solution with equivalent functionality.

The solution is currently in development but we are hoping to have it fully functional by the end of May.

The main decision making script is designed to be run from a Citrix Controller on a scheduled basis.

Prerequisites:

Admin Access to the Citrix Site
WMI Access to the Citrix VDA Servers
There is a separate PowerShell script called “Create Config File”, this is designed to generate the config.xml file that the script reads for all its information about the environment its connecting to.

The Performance Gathering script is rough and ready but currently able to gather Performance Metrics from VDAs.


Chat with us here:
https://gitter.im/Powerscale/community?utm_source=share-link&utm_medium=link&utm_campaign=share-link
