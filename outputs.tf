# variables.tf + tfvars
#        ↓
# main.tf (providers + shared)
#        ↓
# vpc.tf (networking)
#        ↓
# iam.tf (permissions)
#        ↓
# wsus.tf (patch servers)
#        ↓
# ec2.tf (instances)
#        ↓
# inspector.tf (scanning)
#        ↓
# patch_manager.tf (patching rules)
#        ↓
# detection_os.tf (discovery + tagging)