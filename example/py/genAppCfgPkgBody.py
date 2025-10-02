#!/usr/bin/env python3

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# script to generate the body of the AppCfgPkg package which defines
# the USB descriptors

import sys
import os
import stat
import io
import getopt
import re
import yaml

here=os.path.abspath(os.path.dirname(__file__))

sys.path.append(here + '/../../scripts')

import Usb2Desc
import ExampleDevDesc

if __name__ == "__main__":
  fnam                = None

  iProduct            = "Till's Mecatica USB Example Device"


  cmdline             = os.path.basename(sys.argv[0]) + ' ' + ' '.join(sys.argv[1:])

  (opt, args) = getopt.getopt(sys.argv[1:], "hf:d:s:FSN:E:AL:am:U:")
  for o in opt:
    if o[0] in ("-h"):
       print("usage: {} [-h] -f <output_file_or_dir> <config_yaml_file>".format(sys.argv[0]))
       print("          -h               : this message")
       print("          -f file_name     : output file name. If this points to a")
       print("                             directory then the file 'AppCfgPkgBody.vhd'")
       print("                             is generated in this directory.")
       print("          config_yaml_file : YAML file with configuration settings")
       sys.exit(0)
    elif o[0] in ("-f"):
       fnam              = o[1]

  if ( len(args) < 1 ):
    raise RuntimeError("Need a YAML configuration file")

  yamlFileName = args[0]

  # try to stat; raises exception if file does not exist
  fst          = os.stat(yamlFileName)
  dfltName     = 'AppCfgPkgBody.vhd'

  if ( fnam is None ):
    if ( here == os.path.abspath(os.path.dirname(yamlFileName))):
      fnam                = here + '/../hdl/' + dfltName
      print("No output file specified; using: {}".format(fnam))
    else:
      raise RuntimeError("No output file specified; use -f")

  try:
    fst = os.stat(fnam)
    if ( stat.S_ISDIR(fst.st_mode) ):
      if ( fnam[-1] != '/' ):
          fnam += '/'
      print("Generating {} in: {}".format(dfltName, fnam))
      fnam += dfltName
  except FileNotFoundError:
    # they want to generate it, after all
    pass
      


  with io.open(yamlFileName) as f:
    yml = yaml.safe_load(f)

  schema = None
  try:
    import json
    import jsonschema
    with io.open(here + '/schema.json') as f:
      schema = json.load( f )
    jsonschema.validate(yml, schema=schema)
  except jsonschema.exceptions.ValidationError as e:
    print("Schema validation of YAML file failed: {}".format(e.message))
    print(" - from: {}".format(list(e.path)))
    sys.exit(1)
  except BaseException as e:
    print("Warning: unable to validate YAML against schema: ", e.message)

  if yml['deviceDesc']['idProduct'] is None:
    raise RuntimeError(
            "A hex product id *must* be specified in the YAML!\n" +
            "for **private testing only** you may\n\n" +
            "use 0x0001\n\n" +
            "see https://pid.codes/1209/0001/")

  if yml['deviceDesc'].get('iProduct') is None:
    yml['deviceDesc']['iProduct'] = iProduct

  ctxt = ExampleDevDesc.mkExampleDevDescriptors(
              yml,
              ifcNumber=0,
              epAddr=1,
  )

  ymlstr =  yaml.dump( yml, default_flow_style=False ).replace('\n', '\n-- ')
  # strip trailing whitespace
  end = len(ymlstr)
  while ( (end > 0) and (' ' == ymlstr[end-1]) ):
    end -= 1

  comment = "Generated with: '{}':\n--\n-- {}".format( cmdline, ymlstr[:end] )
  with io.open( fnam, 'x' ) as f:
    ctxt.genAppCfgPkgBody( f, comment )
