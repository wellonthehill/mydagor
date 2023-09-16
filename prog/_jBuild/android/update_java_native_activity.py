import os, argparse

import fnmatch

def find_files(directory, pattern):
    for root, dirs, files in os.walk(directory):
        for basename in files:
            if fnmatch.fnmatch(basename, pattern):
                filename = os.path.join(root, basename)
                yield filename

parser = argparse.ArgumentParser()
parser.add_argument('ARG_JAVA_CLASSES_PATH')#1
parser.add_argument('ARG_NATIVE_ACTIVITY')#2

args = parser.parse_args()

for filename in find_files(args.ARG_JAVA_CLASSES_PATH, '*.java'):

  with open(filename, 'r') as origin:
    content = origin.readlines()

  for i in range(len(content)):
    new_line = content[i].replace('{NATIVE_ACTIVITY}', args.ARG_NATIVE_ACTIVITY)
    if new_line!=content[i]:
      print('Found NATIVE_ACTIVITY in FILE {}'.format(filename))
    content[i] = new_line

  with open(filename, 'w+') as output:
    for i in range(len(content)):
      output.write(content[i])