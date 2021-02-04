#!/usr/bin/env python3
from __future__ import absolute_import
import sys
import argparse
import time
from arrow.apollo import get_apollo_instance

parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter, description='''
''')
parser.add_argument('-host', help="Host IP of Apollo2 server", required=True)
parser.add_argument('-organism', help="Organism to be added", required=True)
parser.add_argument('-genus', help="Genus of added Organism", required=True)
parser.add_argument('-species', help="Species of added Organism", required=True)
parser.add_argument('-directory', help="Data directory of added Organism", required=True)
parser.add_argument('-blatdb', help="Blat db of added Organism", required=True)
parser.add_argument('-publicMode', help="publicMode", action='store_true')
parser.add_argument('-token', help="", required=False, default='ignore')
parser.add_argument('-username', help="", required=True)
parser.add_argument('-password', help="", required=True)
 
args = parser.parse_args()

organism = args.organism
commonName = organism
genus = args.genus
species = args.species
directory = args.directory
blatdb = args.blatdb
publicMode = args.publicMode
token = args.token

def organism_exists(commonName):
    """Check if an organism exists
    
    Args:
        commonName: Organism's Common Name
    """
    wa = get_apollo_instance()
    exists = False
    response = wa.organisms.get_organisms()
    if isinstance(response, dict):
        return exists
    elif isinstance(response, list):
        for item in response:
            if item['commonName'] == commonName:
                exists = True
                break
    else:
        raise Exception("Unknown Response from Apollo")

    return exists

def create_organism(commonName, genus, species, directory, blatdb, publicMode, token):
    """Create a new Organism 

    Args:
        commonName: Organism's Common Name
        genus: Organism's Genus
        species: Organism's Species
        directory: Full Path to the Organism's JBrowse data
        blatdb: Full path to blatdb file
        publicMode: ( Boolean ) Should the Organism be visible publicly
        token: Not really sure

    """
    wa = get_apollo_instance()
    try:
        orgs = wa.organisms.add_organism(
            commonName,
            directory,
            blatdb=blatdb,
            genus=genus,
            species=species,
            public=publicMode
        )
    except Exception as e:
        print(f"Error Createing Organism '{organism}' see error below:")
        print(e)
        sys.exit(1)

    return organism_exists(commonName)

def create_groups(organism, genus, species):
    """Create organism specific groups

    Args:
        genus: Organism's Genus
        species: Organism's Species
    """
    wa = get_apollo_instance()
    existing_groups = [group.get("name") for group in wa.groups.get_groups()]
    prefix = f"{genus}_{species}"

    for postfix in ["ADMIN","USER","WRITE"]:
        name = f"{prefix}_{postfix}"
        if not name in existing_groups:
            print(f"Creating Group '{name}'.")
            group_response = wa.groups.create_group(f"{name}")
            time.sleep(2)
            if name in [wa.groups.get_groups(name=name)[0].get("name")]:
                print(f"Group '{name}' successfully created.")
                existing_groups.append(name)

        admin = read = write = export = False
        if postfix == "USER":
            read = True
        elif postfix == "WRITE":
            write = True

        print(f"Update Group Permision for '{name}'")
        perms = wa.groups.update_organism_permissions(name, organism, administrate=admin,
                                              write=write, read=read, export=export)
        time.sleep(1)
    
if organism_exists(commonName):
    print("Create organism: Organism %s existed" % (organism))
else:
    print("Create organism: Organism %s does not exist" % (organism))
    organism_created = create_organism(commonName, genus, species, directory, blatdb, publicMode, token)

create_groups(organism, genus, species)
