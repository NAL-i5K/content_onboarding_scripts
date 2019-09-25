#!/usr/bin/python
from __future__ import absolute_import
from subprocess import Popen, PIPE, call
import json
import sys
import argparse

parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter, description='''
''')
parser.add_argument('-host', help="Host IP of Apollo2 server", required=True)
parser.add_argument('-organism', help="Organism to be added", required=True)
#parser.add_argument('-commonName', help="", required=True)
parser.add_argument('-genus', help="Genus of added Organism", required=True)
parser.add_argument('-species', help="Species of added Organism", required=True)
parser.add_argument('-directory', help="Data directory of added Organism", required=True)
parser.add_argument('-blatdb', help="Blat db of added Organism", required=True)
parser.add_argument('-publicMode', help="publicMode", action='store_true')
parser.add_argument('-token', help="", required=False, default='ignore')
parser.add_argument('-username', help="", required=True)
parser.add_argument('-password', help="", required=True)
 
args = parser.parse_args()

host = args.host
organism = args.organism
commonName = organism
genus = args.genus
species = args.species
directory = args.directory
blatdb = args.blatdb
publicMode = args.publicMode
token = args.token
ADMIN = args.username
PASSWD = args.password
# Usage:
# python createUserBatch.py add_users_groups.txt


def create_findAllOrganism_str():
    curl_str = ["curl", "-i", '-s', "-X", "POST", "-H", "'Content-Type:","application/json'", "-d"]
    curl_cmd =  "'{\"username\":\"" + ADMIN + "\",\"password\":\"" + PASSWD + "\"}'"
    curl_str.append(curl_cmd)
    curl_str.append(host + "/apollo/organism/findAllOrganisms")
    return ' '.join(curl_str)

def create_insertOrganism_str(commonName, genus, species, directory, blatdb, publicMode, token):
    curl_str = ["curl", "-i", '-s', "-X", "POST", "-H", "'Content-Type:","application/json'", "-d"]
    curl_cmd =  "'{\"username\":\"" + ADMIN + "\",\"password\":\"" + PASSWD
    curl_cmd += "\",\"commonName\":\"" + commonName + "\",\"genus\":\"" + genus + "\",\"species\":\"" + species
    curl_cmd += "\",\"directory\":\"" + directory + "\",\"blatdb\":\"" + blatdb + "\",\"publicMode\":\"" + publicMode + "\",\"client_token\":\"" + token +"\"}'"
    curl_str.append(curl_cmd)
    curl_str.append(host + "/apollo/organism/addOrganism")
    return ' '.join(curl_str)

def create_loadGroups_str():
    curl_str = ["curl", "-i", '-s', "-X", "POST", "-H", "'Content-Type:","application/json'", "-d"]
    curl_cmd =  "'{\"username\":\"" + ADMIN + "\",\"password\":\"" + PASSWD + "\"}'"
    curl_str.append(curl_cmd)
    curl_str.append(host + "/apollo/group/loadGroups")
    return ' '.join(curl_str)

def create_createGroup_str(name, organism, token):
    curl_str = ["curl", "-i", '-s', "-X", "POST", "-H", "'Content-Type:","application/json'", "-d"]
    curl_cmd =  "'{\"username\":\"" + ADMIN + "\",\"password\":\"" + PASSWD
    curl_cmd += "\",\"name\":\"" + name + "\",\"organism\":\"" + organism + "\",\"client_token\":\"" + token +"\"}'"
    curl_str.append(curl_cmd)
    curl_str.append(host + "/apollo/group/createGroup")
    return ' '.join(curl_str)

def create_updateOrganismPermission_str(name, organism, admin, read, write, export):
    curl_str = ["curl", "-i", '-s', "-X", "POST", "-H", "'Content-Type:","application/json'", "-d"]
    curl_cmd =  "'{\"username\":\"" + ADMIN + "\",\"password\":\"" + PASSWD
    curl_cmd += "\",\"organism\":\"" + organism + "\",\"name\":\"" + name 
    curl_cmd += "\",\"ADMINISTRATE\":\"" + admin + "\",\"READ\":\"" + read + "\",\"WRITE\":\"" + write + "\",\"EXPORT\":\"" + export +"\"}'"
    curl_str.append(curl_cmd)
    curl_str.append(host + "/apollo/group/updateOrganismPermission")
    return ' '.join(curl_str)


# ADD ORGANISM
p = Popen(create_findAllOrganism_str(), stdout=PIPE, stderr=None, shell=True)
output, err = p.communicate()
msg = output.split('\n')[-1]
d = json.loads(msg)

is_organism_existed = False
for data in d:
    cName = data['commonName']
    if cName == commonName:
        is_organism_existed = True
        o_id = data['id']
        o_genus = data['genus']
        o_species = data['species']
        break

if is_organism_existed:
    print("Create organism: Organism %s existed" % (organism))
else:
    p = Popen(create_insertOrganism_str(commonName, genus, species, directory, blatdb, str(publicMode), token), stdout=PIPE, stderr=None, shell=True)
    output, err = p.communicate()
    msg = output.split('\n')[-1]
    d = json.loads(msg)
    if 'error' in d:
        print("Create organism: fails, error:" + d['error'])
        sys.exit()
    else:
        for data in d:
            cName = data['commonName']
            if cName == commonName:
                o_id = data['id']
                o_genus = data['genus']
                o_species = data['species'] 
                print("Create organism: organism %s created" % (organism))

# ADD GROUPS
p = Popen(create_loadGroups_str(), stdout=PIPE, stderr=None, shell=True)
output, err = p.communicate()
msg = output.split('\n')[-1]
d = json.loads(msg)
is_group_admin_existed = False
is_group_read_existed = False
is_group_write_existed = False
group_admin_name = genus + '_' + species + "_ADMIN"
group_read_name  = genus + '_' + species + "_USER"
group_write_name = genus + '_' + species + "_WRITE"

for data in d:
    if data['name'] == group_admin_name:
        print("Create group: group %s existed" % (group_admin_name))
        is_group_admin_existed = True
    elif data['name'] == group_read_name:
        print("Create group: group %s existed" % (group_read_name))
        is_group_read_existed = True
    elif data['name'] == group_write_name:
        print("Create group: group %s existed" % (group_write_name))
        is_group_write_existed = True

if not is_group_admin_existed:
   p = Popen(create_createGroup_str(group_admin_name, organism, token), stdout=PIPE, stderr=None, shell=True) 
   output, err = p.communicate()
   print("Create group: group %s created" % (group_admin_name))

if not is_group_read_existed:
   p = Popen(create_createGroup_str(group_read_name, organism, token), stdout=PIPE, stderr=None, shell=True) 
   output, err = p.communicate()
   print("Create group: group %s created" % (group_read_name))
 
if not is_group_write_existed:
   p = Popen(create_createGroup_str(group_write_name, organism, token), stdout=PIPE, stderr=None, shell=True) 
   output, err = p.communicate()
   print("Create group: group %s created" % (group_write_name))
 
# ADD PERMISSIONS
print("Update permission")
p = Popen(create_updateOrganismPermission_str(group_admin_name, organism, 'False', 'False', 'False', 'False'), stdout=PIPE, stderr=None, shell=True)
output_p, err_p = p.communicate()

p = Popen(create_updateOrganismPermission_str(group_read_name, organism, 'False', 'True', 'False', 'False'), stdout=PIPE, stderr=None, shell=True)
output_p, err_p = p.communicate()

p = Popen(create_updateOrganismPermission_str(group_write_name, organism, 'False', 'False', 'True', 'False'), stdout=PIPE, stderr=None, shell=True)
output_p, err_p = p.communicate()
