# PowerScale
<img src="https://www.leeejeffries.com/wp-content/uploads/2019/05/logo_small.jpg" alt="PowerScale icon" style="float: left; margin-right: 10px;" />
Citrix currently have a product called SmartScale, this product is being put out to pasture at the end of May.

The idea of PowerScale is to provide a solution with equivalent functionality.

The solution is now ready for release at Version 1.0.

The main decision making script is designed to be run from a Citrix Controller or VM with Studio installed on a scheduled basis.

Prerequisites:
- Admin Access to the Citrix Site from the user creating is script
- WMI Access to the Citrix VDA Servers or an account that has access (Can be specified in the config file)
 - There is a separate PowerShell script called “Create Config File”, this is designed to generate the config.xml file that the script reads for all its information about the environment its connecting to.

Please make sure on your initial test runs you enable test mode, this will gather information but not perform any actions on the farm. This will also confirm that WMI access is working as expected.

Chat with us here:
https://gitter.im/Powerscale/community?utm_source=share-link&utm_medium=link&utm_campaign=share-link
