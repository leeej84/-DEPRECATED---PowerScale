# PowerScale
<div><img src="https://www.leeejeffries.com/wp-content/uploads/2019/05/logo_small.jpg" alt="PowerScale icon" width="250px" height="200px" style="margin-right: 10px;" />

<img src="https://www.leeejeffries.com/wp-content/uploads/2019/08/RDTabs_IMURKMZWwa-1024x486.png" alt="PowerScale Dashboard" style="margin-right: 10px;" /></div>

Citrix had a product called SmartScale, this product was put out to pasture at the end of July.

The idea of PowerScale is to provide a solution with equivalent functionality.

The main decision making script is designed to be run from a Citrix Controller or VM with Studio installed on a scheduled basis.

Prerequisites:
- Admin Access to the Citrix Site from the user creating is script
- PSMAN Access to the Citrix VDA Servers or an account that has access (Can be specified in the config file)
 - There is a separate PowerShell script called “Create Config File”, this is designed to generate the config.xml file that the script reads for all its information about the environment its connecting to.

Please make sure on your initial test runs you enable test mode, this will gather information but not perform any actions on the farm. This will also confirm that PSMAN access is working as expected.

https://worldofeuc.slack.com/messages/CLCSCA8LR

Join the project-powerscale channel


