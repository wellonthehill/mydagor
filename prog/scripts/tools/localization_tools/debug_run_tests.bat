@REM This batch file is for validation scripts debugging. It is for use by programmers only.
@REM It validates localizaton files in local "tests" dir only, and writes results into local "result.txt" file.
@echo off
setlocal
set PARAMS_JSON="{\"root\":\".\",\"scan\":[\"tests\"],\"verbose\":true,\"isDebugTest\":true}"
echo require("langs_validation.nut").validateLangs(parse_json(%PARAMS_JSON%)) > _temp.nut
..\..\..\..\tools\dagor3_cdk\util\csq-dev.exe _temp.nut | tee result.txt
del /Q _temp.nut
endlocal
