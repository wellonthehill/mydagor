@echo off
for /D %%D in (userSkins/*) do (
  echo ---- %%D
  for %%f in ("userSkins/%%~D/*.blk") do ..\..\..\..\tools\dagor3_cdk\bin64\customContentTool-dev cfg_user_skin.blk "%%~D" "userSkins/%%~D/%%~f"
)
