Welcome to PowerScale

PowerScale is a replacement for Citrix Smart Scale due to go end of life End of May 2019.

This repository currently has 3 scripts:
1. Create Config File.ps1 - Designed to creat an XML config file from scratch that can be used by the main decision making script.
2. Decision Making.ps1 - The main logic script run on a schedule basis from a Citrix Controller.
3. Performance Measurement.ps1 - Gathers performance information from VDAs to make a decision on scaling.

Features that currently work:
 - Inside of working hours machine startup
 - Outside of working hours machine shutdown
 
 At present machines are select via a naming prefix.
 
 The following prerequisites are necessary:
 1. Admin Access to the Citrix Site
 2. WMI Access to query Citrix VDA's
 
