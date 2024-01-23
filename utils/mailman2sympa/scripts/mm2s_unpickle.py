#!/usr/bin/python2

import sys
import pickle
import json
import os

mm_path=os.getenv('MAILMAN_HOME', '/usr/share/mailman')
sys.path.insert(1,mm_path)
filename = sys.argv[1]
infile = open(filename,'rb')
while True:
    try:
        config_dict = pickle.load(infile)
    except EOFError:
        break
    except pickle.UnpicklingError:
        print(
                _('Not a Mailman 2.1 configuration file: $infile'))
    else:
        if not isinstance(config_dict, dict):
            print(_('Ignoring non-dictionary: {0!r}').format(
                config_dict))
            continue
config_dict['bounce_info'] = str(config_dict.get('bounce_info'))
print(json.dumps(config_dict))
infile.close()
