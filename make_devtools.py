import sys

if sys.version_info.major < 3:
  print("\nERROR: Python 3 or a higher version is required to run this script.")
  exit(1)

import subprocess
import pathlib
import os
import urllib
import ssl
import ctypes
import zipfile
import shutil
from urllib import request


if len(sys.argv) != 2:
  print('\nUsage: make_devtools.py DEVTOOLS_DEST_DIR\nexample: python3 make_devtools.py d:\\devtools\n')
  exit(1)

def error(s):
  print(f"\nERROR: {s}\n")
  exit(1)

def ask(s):
  while True:
    answer = input(f"\n{s} [Y/n]: ").strip().lower()
    if answer == "y" or answer == "y" or answer == "":
      return True
    if answer == "n" or answer == "no":
      return False

def contains_spaces(s):
  return ' ' in s

def contains_non_ascii(s):
  try:
    s.encode('ascii')
  except UnicodeEncodeError:
    return True
  return False

dest_dir = sys.argv[1].replace('\\', '/').rstrip('/')

if contains_spaces(dest_dir):
  error("The destination directory contains spaces, which are not allowed in a file path.")

if contains_non_ascii(dest_dir):
  error("The destination directory contains non-ASCII characters.")

if not os.path.isabs(dest_dir):
  error("The destination directory must be an absolute path.")


def make_directory_symlink(src, dest):
  try:
    subprocess.run(['cmd', '/C', 'mklink', '/J', os.path.normpath(dest), os.path.normpath(src)], shell = True, check = True)
  except subprocess.CalledProcessError as e:
    error(f"Symlink command failed with a non-zero exit code. Error: {e}, Source = '{src}', Destination = '{dest}'")
  except OSError as e:
    print(f"An OSError occurred. Symlink command may have failed. Error: {e}, Source = '{src}', Destination = '{dest}'")

def make_file_link(src, dest):
  os.link(src, dest)

def run(cmd):
  try:
    print(f"Running: {cmd}")
    subprocess.run(cmd, shell = True, check = True)
  except subprocess.CalledProcessError as e:
    error(f"subprocess.run failed with a non-zero exit code. Error: {e}")
  except OSError as e:
    print(f"An OSError occurred, subprocess.run command may have failed. Error: {e}")


ssl._create_default_https_context = ssl._create_unverified_context

def download_url2(url, file):
  file = "{0}/.packages/{1}".format(dest_dir, file)
  if not pathlib.Path(file).exists():
    print("Downloading '{0}' to '{1}' ...".format(url, file));
    response = request.urlretrieve(url, file)
  else:
    print(f"Package '{file}' already exists");

def download_url(url):
  path, file = os.path.split(os.path.normpath(url))
  download_url2(url, file)

pathlib.Path(dest_dir).mkdir(parents=True, exist_ok=True)
pathlib.Path(dest_dir+'/.packages').mkdir(parents=True, exist_ok=True)

# python3
python_dest_folder = dest_dir+'/python3'
if pathlib.Path(python_dest_folder).exists():
  print('=== Python 3 symlink found at {0}, skipping setup'.format(python_dest_folder))
else:
  python_src_folder = os.path.dirname(sys.executable)
  if not pathlib.Path(python_src_folder+'/python.exe').exists():
    python_src_folder = os.environ.get('LOCALAPPDATA', '') + '/Programs/Python'
  if pathlib.Path(python_src_folder).exists():
    if not pathlib.Path(python_src_folder+'/python.exe').exists():
      for item in pathlib.Path(python_src_folder).glob("Python3*"):
        if item.is_dir():
          if pathlib.Path(os.path.normpath(item)+'/python.exe').exists():
            python_src_folder = os.path.normpath(item)
            break
    print('+++ Python 3 found at {0}'.format(python_src_folder))
    make_directory_symlink(python_src_folder, python_dest_folder)

    subprocess.run([python_dest_folder+'/python.exe', '-m', 'pip', 'install', '--upgrade', 'pip'])
    subprocess.run([python_dest_folder+'/python.exe', '-m', 'pip', '--version'])
    subprocess.run([python_dest_folder+'/python.exe', '-m', 'pip', 'install', 'clang==14.0.6'])
    subprocess.run([python_dest_folder+'/python.exe', '-m', 'pip', 'install', 'cymbal'])
    if not pathlib.Path(python_dest_folder+'/python3.exe').exists():
      make_file_link(python_dest_folder+'/python.exe', python_dest_folder+'/python3.exe')
  else:
    error("Python 3 not found")


microsoft_retry = []

# vs140
def setup_vs140(check_again_after_download):
  vc2015_dest_folder = dest_dir+'/vc2015.3'
  if pathlib.Path(vc2015_dest_folder).exists():
    print('=== VC2015 symlink found at {0}, skipping setup'.format(vc2015_dest_folder))
  else:
    vc2015_src_folder = os.environ.get('VS140COMNTOOLS', '')
    if vc2015_src_folder != '':
      vc2015_src_folder = os.path.normpath(vc2015_src_folder+'/../..')
    else:
      vc2015_src_folder = '{0}/Microsoft Visual Studio 14.0'.format(os.environ['ProgramFiles(x86)'])

    if vc2015_src_folder and pathlib.Path(vc2015_src_folder).exists():
      print('+++ VC2015 found at {0}'.format(vc2015_src_folder))
      make_directory_symlink(vc2015_src_folder+'/VC', vc2015_dest_folder)
    else:
      print('--- VC2015 not found (VS140COMNTOOLS env var is empty), install VisualStudio 2015 upd.3 and re-run setup')
      if not check_again_after_download:
        error(f"Visual Studio 2015 is required but not found at '{vc2015_src_folder}'")
      microsoft_retry.append(setup_vs140)

#Visual Studio 2015 is turned off
#setup_vs140(True)


# vs142
def setup_vs142(check_again_after_download):
  vs142_ver = "14.29"
  vc2019_dest_folder = dest_dir + '/vc2019_16.10.3'

  if pathlib.Path(vc2019_dest_folder).exists():
    real_path = ""
    try:
      real_path = os.path.realpath(vc2019_dest_folder)
    except OSError as e:
      pass

    if (not pathlib.Path(vc2019_dest_folder + '/bin/HostX64/x64/1033').exists() or
       (real_path.find("Microsoft") != -1 and real_path.find(vs142_ver) == -1)):
      print(f"{vc2019_dest_folder} contains invalid version of build tools.")
      print(f"...removing {vc2019_dest_folder}")
      try:
        os.remove(vc2019_dest_folder)
      except OSError as e:
        error(f"Cannot remove link {vc2019_dest_folder}: {e}")


  if pathlib.Path(vc2019_dest_folder).exists():
    print('=== VC2019 symlink found at {0}, skipping setup'.format(vc2019_dest_folder))
  else:
    ok = False
    vc2019_src_folder = '{0}/Microsoft Visual Studio'.format(os.environ['ProgramFiles(x86)'])
    if vc2019_src_folder and pathlib.Path(vc2019_src_folder).exists():
      for nm in ['/2022/BuildTools', '/2022/Community', '/2022/Enterprise', '/2022/Professional',
                 '/2019/BuildTools', '/2019/Community', '/2019/Enterprise', '/2019/Professional']:
        if pathlib.Path(vc2019_src_folder + nm + '/VC/Tools/MSVC').exists():
          versions_folder = vc2019_src_folder + nm + '/VC/Tools/MSVC'
          for item in pathlib.Path(versions_folder).glob(vs142_ver + ".*"):
            if item.is_dir():
              if pathlib.Path(os.path.normpath(item)+'/bin/HostX64/x64/1033').exists():
                if pathlib.Path(os.path.normpath(item)+'/bin/HostX86/x86/1033').exists():
                  vc2019_src_folder = os.path.normpath(item)
                  ok = True
                  break

    if ok:
      print('+++ VC2019 found at {0}'.format(vc2019_src_folder))
      make_directory_symlink(vc2019_src_folder, vc2019_dest_folder)
    else:
      print('--- VC2019 not found, install VisualStudio 2019 16.10.3+ and re-run setup')
      if not check_again_after_download:
        error(f"Visual Studio 2019 is required but not found at '{vc2019_src_folder}'")
      microsoft_retry.append(setup_vs142)


setup_vs142(True)


# Microsoft Windows 10 SDK
def setup_winsdk_100(check_again_after_download):
  winsdk_dest_folder = dest_dir+'/win.sdk.100'
  if pathlib.Path(winsdk_dest_folder).exists():
    print('=== Windows 10 SDK symlink found at {0}, skipping setup'.format(winsdk_dest_folder))
  else:
    winsdk_src_folder = '{0}/Windows Kits/10'.format(os.environ['ProgramFiles(x86)'])
    if pathlib.Path(winsdk_src_folder+'/include/10.0.19041.0').exists():
      print('+++ Windows 10 SDK found at {0}'.format(winsdk_src_folder))
      make_directory_symlink(winsdk_src_folder, winsdk_dest_folder)
    else:
      print('--- Windows 10 SDK not found, install Windows SDK and re-run setup')
      if not check_again_after_download:
        error(f"Windows 10 SDK is required but not found at '{winsdk_src_folder}'")
      microsoft_retry.append(setup_winsdk_100)

setup_winsdk_100(True)


# Microsoft Windows 8.1 SDK
def setup_winsdk_81(check_again_after_download):
  winsdk_dest_folder = dest_dir+'/win.sdk.81'
  if pathlib.Path(winsdk_dest_folder).exists():
    print('=== Windows 8.1 SDK symlink found at {0}, skipping setup'.format(winsdk_dest_folder))
  else:
    winsdk_src_folder = '{0}/Windows Kits/8.1'.format(os.environ['ProgramFiles(x86)'])
    if pathlib.Path(winsdk_src_folder+'/include').exists():
      print('+++ Windows 8.1 SDK found at {0}'.format(winsdk_src_folder))
      make_directory_symlink(winsdk_src_folder, winsdk_dest_folder)
    else:
      print('--- Windows 8.1 SDK not found, install Windows SDK and re-run setup')
      if not check_again_after_download:
        error(f"Windows 8.1 SDK is required but not found at '{winsdk_src_folder}'")

      pathlib.Path(f"{dest_dir}/.packages/vs140").mkdir(parents=True, exist_ok=True)
      download_url2("https://aka.ms/vs/15/release/vs_buildtools.exe", f"vs140/vs_buildtools.exe")
      run(f"{dest_dir}/.packages/vs140/vs_buildtools.exe --wait --passive --add " +
           "Microsoft.VisualStudio.Component.Windows81SDK ")
      setup_winsdk_81(False)

setup_winsdk_81(True)


if len(microsoft_retry) > 0:
  download_url('https://aka.ms/vs/17/release/vs_buildtools.exe')
  run(f"{dest_dir}/.packages/vs_buildtools.exe --wait --passive --addProductLang en-US --add " +
    " Microsoft.VisualStudio.Component.Roslyn.Compiler" +
    " Microsoft.Component.MSBuild" +
    " Microsoft.VisualStudio.Component.CoreBuildTools" +
    " Microsoft.VisualStudio.Workload.MSBuildTools" +
    " Microsoft.VisualStudio.Component.Windows10SDK" +
    " Microsoft.VisualStudio.Component.VC.CoreBuildTools" +
    " Microsoft.VisualStudio.Component.VC.Redist.14.Latest" +
    " Microsoft.VisualStudio.Component.TestTools.BuildTools" +
    " Microsoft.Net.Component.4.7.2.TargetingPack" +
    " Microsoft.VisualStudio.Component.VC.ASAN" +
    " Microsoft.VisualStudio.Component.TextTemplating" +
    " Microsoft.VisualStudio.Component.VC.CoreIde" +
    " Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core" +
    " Microsoft.VisualStudio.Component.Windows10SDK.19041" +
    " Microsoft.VisualStudio.ComponentGroup.VC.Tools.142.x86.x64" +
    " Microsoft.Component.VC.Runtime.UCRTSDK" +
    " Microsoft.VisualStudio.Component.VC.140" +
    " Microsoft.VisualStudio.Workload.VCTools" +
    " Microsoft.VisualStudio.Component.VC.14.29.16.11.x86.x64" +
    " Microsoft.VisualStudio.Component.VC.14.29.16.11.ATL" )

  for fn in microsoft_retry:
    fn(False)



# LLVM 15.0.7
llvm_dest_folder = dest_dir+'/LLVM-15.0.7'
if pathlib.Path(llvm_dest_folder).exists():
  print('=== LLVM 15.0.7 symlink found at {0}, skipping setup'.format(llvm_dest_folder))
else:
  llvm_src_folder = '{0}/LLVM'.format(os.environ['ProgramFiles']) #(x86)
  if not pathlib.Path(llvm_src_folder+'/bin').exists():
    print('--- LLVM 15.0.7 not found, trying to install')
    download_url('https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.7/LLVM-15.0.7-win64.exe')
    run(dest_dir+'/.packages/LLVM-15.0.7-win64.exe /S')

  if pathlib.Path(llvm_src_folder+'/bin').exists():
    print('+++ LLVM 15.0.7 found at {0}'.format(llvm_src_folder))
    make_directory_symlink(llvm_src_folder, llvm_dest_folder)
  else:
    error("LLVM 15.0.7 not found")


# nasm
nasm_dest_folder = dest_dir+'/nasm'
if pathlib.Path(nasm_dest_folder).exists():
  print('=== NASM symlink found at {0}, skipping setup'.format(nasm_dest_folder))
else:
  download_url('https://www.nasm.us/pub/nasm/releasebuilds/2.16/win64/nasm-2.16-win64.zip')
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/nasm-2.16-win64.zip'), 'r') as zip_file:
    zip_file.extractall(dest_dir)
    make_directory_symlink(dest_dir+'/nasm-2.16', nasm_dest_folder)
    shutil.copyfile(nasm_dest_folder+'/nasm.exe', nasm_dest_folder+'/nasmw.exe')
    shutil.copyfile(nasm_dest_folder+'/ndisasm.exe', nasm_dest_folder+'/ndisasmw.exe')
    print('+++ NASM 2.16 installed at {0}'.format(nasm_dest_folder))


# ducible
ducible_dest_file = dest_dir+'/ducible.exe'
if pathlib.Path(ducible_dest_file).exists():
  print('=== Ducible tool found at {0}, skipping setup'.format(ducible_dest_file))
else:
  download_url('https://github.com/jasonwhite/ducible/releases/download/v1.2.2/ducible-windows-x64-Release.zip')
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/ducible-windows-x64-Release.zip'), 'r') as zip_file:
    zip_file.extractall(dest_dir)
    print('+++ Ducible tool installed at {0}'.format(dest_dir))


# boost-1.62
def install_boost_1_62():
  boost_dest_folder = dest_dir+'/boost-1.62'
  if pathlib.Path(boost_dest_folder).exists():
    print('=== boost-1.62 found at {0}, skipping setup'.format(boost_dest_folder))
  else:
    boost_src_folder = ''
    for loc in ['c:/local']:
      for item in pathlib.Path(loc).glob("boost_1_62*"):
        if item.is_dir():
          if pathlib.Path(os.path.normpath(item)+'/boost').exists():
            boost_src_folder = os.path.normpath(item)
            break

    if boost_src_folder != '':
      print('+++ boost-1.62 found at {0}'.format(boost_src_folder))
      make_directory_symlink(boost_src_folder, boost_dest_folder)
    else:
      download_url('https://sourceforge.net/projects/boost/files/boost/1.62.0/boost_1_62_0.zip')
      with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/boost_1_62_0.zip'), 'r') as zip_file:
        zip_file.extractall(dest_dir)
        pathlib.Path(dest_dir+'/boost-1.62/libs').mkdir(parents=True, exist_ok=True)
        subprocess.run(['cmd', '/C', 'move',
          os.path.normpath(dest_dir+'/boost_1_62_0/boost'), os.path.normpath(dest_dir+'/boost-1.62/')])
        for d in ['date_time', 'filesystem', 'system', 'thread']:
          pathlib.Path(dest_dir+'/boost-1.62/libs/'+d).mkdir(parents=True, exist_ok=True)
          subprocess.run(['cmd', '/C', 'move',
            os.path.normpath(dest_dir+'/boost_1_62_0/libs/'+d+'/src'), os.path.normpath(dest_dir+'/boost-1.62/libs/'+d)])
        subprocess.run(['cmd', '/C', 'rmdir', '/S', '/Q', os.path.normpath(dest_dir+'/boost_1_62_0')])
        print('+++ boost-1.62 installed at {0}'.format(boost_dest_folder))

#install_boost_1_62()


# 3ds Max SDK
def install_3ds_Max_SDK(ver, url):
  maxsdk_dest_folder = dest_dir+'/max'+ver+'.sdk'
  if pathlib.Path(maxsdk_dest_folder).exists():
    print('=== 3ds Max SDK {1} symlink found at {0}, skipping setup'.format(maxsdk_dest_folder, ver))
  else:
    if ask(f"Do you want to install 3ds Max {ver} SDK?"):
      maxsdk_src_folder = '{0}/Autodesk/3ds Max {1} SDK'.format(os.environ['ProgramFiles'], ver)
      if not pathlib.Path(maxsdk_src_folder+'/maxsdk').exists():
        print('--- 3ds Max SDK '+ver+' not found, trying to install')
        download_url(url)
        path, file = os.path.split(os.path.normpath(url))
        run('msiexec /i ' + os.path.normpath(dest_dir + '/.packages/' + file) + ' /qb')

      if pathlib.Path(maxsdk_src_folder+'/maxsdk').exists():
        print('+++ 3ds Max SDK {1} found at {0}'.format(maxsdk_src_folder, ver))
        make_directory_symlink(maxsdk_src_folder+'/maxsdk', maxsdk_dest_folder)
      else:
        print('--- 3ds Max SDK {1} not found at {0}, skipped setup'.format(maxsdk_src_folder, ver))

install_3ds_Max_SDK('2024',
  'https://autodesk-adn-transfer.s3.us-west-2.amazonaws.com/ADN+Extranet/M%26E/Max/Autodesk+3ds+Max+2024/SDK_3dsMax2024.msi')
install_3ds_Max_SDK('2023',
  'https://autodesk-adn-transfer.s3.us-west-2.amazonaws.com/ADN+Extranet/M%26E/Max/Autodesk+3ds+Max+2023/SDK_3dsMax2023.msi')
#install_3ds_Max_SDK('2019',
#  'https://autodesk-adn-transfer.s3.us-west-2.amazonaws.com/ADN%20Extranet/M%26E/Max/Autodesk%203ds%20Max%202019/SDK_3dsMax2019.msi')


# FMOD
fmod_dest_folder = dest_dir+'/fmod-studio-2.xx.xx'
if pathlib.Path(fmod_dest_folder).exists():
  print('=== FMOD symlinks found at {0}, skipping setup'.format(fmod_dest_folder))
else:
  fmod_src_folder = '{0}/FMOD SoundSystem/FMOD Studio API Windows'.format(os.environ['ProgramFiles(x86)'])
  if pathlib.Path(fmod_src_folder).exists():
    print('+++ FMOD found at {0}'.format(fmod_src_folder))

    pathlib.Path(fmod_dest_folder+'/core/win32').mkdir(parents=True, exist_ok=True)
    make_directory_symlink(fmod_src_folder+'/api/core/inc', fmod_dest_folder+'/core/win32/inc')
    make_directory_symlink(fmod_src_folder+'/api/core/lib/x86', fmod_dest_folder+'/core/win32/lib')

    pathlib.Path(fmod_dest_folder+'/core/win64').mkdir(parents=True, exist_ok=True)
    make_directory_symlink(fmod_src_folder+'/api/core/inc', fmod_dest_folder+'/core/win64/inc')
    make_directory_symlink(fmod_src_folder+'/api/core/lib/x64', fmod_dest_folder+'/core/win64/lib')

    pathlib.Path(fmod_dest_folder+'/studio/win32').mkdir(parents=True, exist_ok=True)
    make_directory_symlink(fmod_src_folder+'/api/studio/inc', fmod_dest_folder+'/studio/win32/inc')
    make_directory_symlink(fmod_src_folder+'/api/studio/lib/x86', fmod_dest_folder+'/studio/win32/lib')

    pathlib.Path(fmod_dest_folder+'/studio/win64').mkdir(parents=True, exist_ok=True)
    make_directory_symlink(fmod_src_folder+'/api/studio/inc', fmod_dest_folder+'/studio/win64/inc')
    make_directory_symlink(fmod_src_folder+'/api/studio/lib/x64', fmod_dest_folder+'/studio/win64/lib')
  else:
    print('--- FMOD not found at {0}, creating stub folders'.format(fmod_src_folder))
    print('consider downloading and installing https://www.fmod.com/download#fmodengine - Windows Download')
    pathlib.Path(fmod_dest_folder+'/core/win32/inc').mkdir(parents=True, exist_ok=True)
    pathlib.Path(fmod_dest_folder+'/core/win64/inc').mkdir(parents=True, exist_ok=True)
    pathlib.Path(fmod_dest_folder+'/studio/win32/inc').mkdir(parents=True, exist_ok=True)
    pathlib.Path(fmod_dest_folder+'/studio/win64/inc').mkdir(parents=True, exist_ok=True)


# OpenXR 1.0.16
openxr_dest_folder = dest_dir+'/openxr-1.0.16'
if pathlib.Path(openxr_dest_folder).exists():
  print('=== OpenXR symlink found at {0}, skipping setup'.format(openxr_dest_folder))
else:
  download_url('https://github.com/KhronosGroup/OpenXR-SDK-Source/releases/download/release-1.0.16/openxr_loader_windows-1.0.16.zip')
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/openxr_loader_windows-1.0.16.zip'), 'r') as zip_file:
    zip_file.extractall(openxr_dest_folder)
    make_directory_symlink(openxr_dest_folder+'/openxr_loader_windows/include', openxr_dest_folder+'/include')
    make_directory_symlink(openxr_dest_folder+'/openxr_loader_windows/Win32', openxr_dest_folder+'/win32')
    make_directory_symlink(openxr_dest_folder+'/openxr_loader_windows/x64', openxr_dest_folder+'/win64')
    print('+++ OpenXR 1.0.16 installed at {0}'.format(openxr_dest_folder))


# FidelityFX-FSR2 compiler
ffxsc_dest_folder = dest_dir+'/FidelityFX_SC'
if pathlib.Path(ffxsc_dest_folder).exists():
  print('=== FidelityFX_SC symlink found at {0}, skipping setup'.format(ffxsc_dest_folder))
else:
  download_url2('https://github.com/GPUOpen-Effects/FidelityFX-FSR2/archive/refs/tags/v2.2.1.zip', 'FidelityFX-FSR2.zip')
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/FidelityFX-FSR2.zip'), 'r') as zip_file:
    zip_file.extractall(dest_dir+'/.packages/')
    make_directory_symlink(dest_dir+'/.packages/FidelityFX-FSR2-2.2.1/tools/sc', ffxsc_dest_folder)
    print('+++ FidelityFX_SC 2.2.1 installed at {0}'.format(ffxsc_dest_folder))


# DXC-1.7.2207
dxc_dest_folder = dest_dir+'/DXC-1.7.2207'
if pathlib.Path(dxc_dest_folder).exists():
  print('=== DXC Jul 2022 found at {0}, skipping setup'.format(dxc_dest_folder))
else:
  download_url('https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.7.2207/dxc_2022_07_18.zip')
  download_url('https://github.com/microsoft/DirectXShaderCompiler/archive/refs/tags/v1.7.2207.zip')
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/v1.7.2207.zip'), 'r') as zip_file:
    zip_file.extractall(dest_dir+'/.packages/')
    with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/dxc_2022_07_18.zip'), 'r') as zip_file:
      zip_file.extractall(dest_dir+'/.packages/DirectXShaderCompiler-1.7.2207/_win')

      pathlib.Path(dxc_dest_folder+'/include').mkdir(parents=True, exist_ok=True)
      pathlib.Path(dxc_dest_folder+'/lib/win64').mkdir(parents=True, exist_ok=True)
      make_directory_symlink(dest_dir+'/.packages/DirectXShaderCompiler-1.7.2207/include/dxc', dxc_dest_folder+'/include/dxc')
      shutil.copyfile(dest_dir+'/.packages/DirectXShaderCompiler-1.7.2207/_win/bin/x64/dxcompiler.dll', dxc_dest_folder+'/lib/win64/dxcompiler.dll')
      shutil.copyfile(dest_dir+'/.packages/DirectXShaderCompiler-1.7.2207/LICENSE.TXT', dxc_dest_folder+'/LICENSE.TXT')
      print('+++ DXC Jul 2022 installed at {0}'.format(dxc_dest_folder))


# re-write platform.jam
if pathlib.Path('prog/platform.jam').exists():
  with open('prog/platform.jam', 'w') as fd:
    fd.write('_DEVTOOL = {0} ;\n'.format(dest_dir))
    fd.write('CODE_CHECK = rem ;\n')
    fd.write('FmodStudio = 2.xx.xx ;\n')
    fd.write('BulletSdkVer = 3 ;\n')
    fd.write('OpenSSLVer = 3.x ;\n')
    fd.close()


nomalized_dest = os.path.normpath(dest_dir)
env_updated = False

if os.environ.get('GDEVTOOL', '') == '':
  if ask("Environment variable 'GDEVTOOL' not found. Do you want to set it?"):
    subprocess.run(["setx", "GDEVTOOL", nomalized_dest], shell=True, text=True)
    os.environ["GDEVTOOL"] = nomalized_dest
    env_updated = True
elif os.environ.get('GDEVTOOL', '') != nomalized_dest:
  if ask("Environment variable 'GDEVTOOL' points to another directory. Do you want to update it?"):
    subprocess.run(["setx", "GDEVTOOL", nomalized_dest], shell=True, text=True)
    os.environ["GDEVTOOL"] = nomalized_dest
    env_updated = True

if nomalized_dest not in os.environ.get('PATH', '').split(os.pathsep):
  if ask(f"'{nomalized_dest}' is not found in 'PATH' variable. Do you want to add it?"):
    subprocess.run(["setx", "PATH", f"{nomalized_dest};{os.environ.get('PATH', '')}"], shell=True, text=True)
    os.environ["PATH"] = os.environ.get('PATH', '') + ";" + nomalized_dest
    env_updated = True

try:
  subprocess.run(["jam", "-v"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
except FileNotFoundError:
  print("jam.exe not found, installing jam...")
  download_url2("https://github.com/GaijinEntertainment/jam-G8/releases/download/2.5-G8-1.2-2023%2F05%2F04/jam-win64.zip", "jam.zip")
  with zipfile.ZipFile(os.path.normpath(dest_dir+'/.packages/jam.zip'), 'r') as zip_file:
    zip_file.extractall(dest_dir)

if env_updated:
  print("\nDone. Please restart your comandline environment to apply the environment variables.")
else:
  print("\nDone.")
