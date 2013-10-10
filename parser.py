#    Copyright (c) 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import os
import yaml
import logging as log
from manifest import Manifest
from consts import DIRECTORIES_BY_TYPE, DATA_TYPES


class ManifestParser(object):
    def __init__(self, manifest_directory):
        self.manifest_directory = manifest_directory

    def parse(self):
        manifests = []
        for file in os.listdir(self.manifest_directory):
            manifest_file = os.path.join(self.manifest_directory, file)
            if os.path.isfile(manifest_file):
                if not file.endswith(".yaml"):
                    log.warning("Extention of {0} file is not yaml. "
                                "Only yaml file supported for "
                                "service manifest files.".format(file))
                    continue

                try:
                    with open(manifest_file) as stream:
                        service_manifest_data = yaml.load(stream)
                except yaml.YAMLError, exc:
                        log.warn("Failed to load manifest file. {0}. "
                                 "The reason: {1!s}".format(manifest_file,
                                                            exc))
                        continue

                for key, value in service_manifest_data.iteritems():
                    valid_file_info = True
                    if key in DATA_TYPES:
                        root_directory = DIRECTORIES_BY_TYPE.get(key)
                        if not isinstance(value, list):
                            log.error("{0} section should represent a file"
                                      " listing in manifest {1}"
                                      "".format(root_directory, file))
                            valid_file_info = False
                            continue
                        for i, filename in enumerate(value):
                            absolute_path = os.path.join(root_directory,
                                                         filename)

                            service_manifest_data[key][i] = absolute_path

                            if not os.path.exists(absolute_path):
                                valid_file_info = False
                                log.warning(
                                    "File {0} specified in manifest {1} "
                                    "doesn't exist at {2}".format(filename,
                                                                  file,
                                                                  absolute_path
                                                                  ))
                service_manifest_data["valid"] = valid_file_info

                manifests.append(Manifest(service_manifest_data))
        return manifests
