from ansible.errors import AnsibleFilterError

def flatten_emcli_metrics(d, config_type='metric', parent_keys=list(), separator='_', type='metric'):
    """
    A custom filter to flatten the oem_metrics dictionary into a list
    of properties indexed by target_type and target_name.

    We pass in the configuration type which may be one of:

    * metric:            EMCLI Metrics Input File
    * schedule:          Metric Collection Scheduler Attributes
    * custom_properties: Properties which are not supported by EMCLI Metrics Input Files

    We assume the structure is:

    oem_metrics:
         target_type:
            target_name|all:
                schedule: 
                   <collection name>: 
                       <collection attribute>: <collection attribute value>
                input_file: <EMCLI input file>
                custom_properties:
                    <property name>: <property value>

    """
    items = []

    for k, v in d.items():
        new_keys = parent_keys + [k]
        if isinstance(v, dict):
            items.extend(flatten_emcli_metrics(v, config_type, new_keys, separator=separator))
        else:
            if config_type == 'metric' and new_keys[-1] == 'input_file':
                    item = {'target_type': None, 'target_name': None, 'input_file': v}
                    if len(new_keys) >= 3:
                        item['target_name'] = new_keys[-2]
                        item['target_type'] = new_keys[-3]
                    items.append(item)
            elif config_type == 'schedule' and new_keys[-3] == 'schedule':
                    item = {'target_type': None, 'target_name': None, 'collection_name': None, 'collection_attribute': None, 'collection_attribute_value': v}
                    if len(new_keys) >= 5:
                        item['collection_attribute'] = new_keys[-1]
                        item['collection_name'] = new_keys[-2]
                        item['target_name'] = new_keys[-4]
                        item['target_type'] = new_keys[-5]
                    items.append(item)
            elif config_type == 'custom_properties' and new_keys[-2] == 'custom_properties':
                    item = {'target_type': None, 'target_name': None, 'property_name': None, 'property_value': v}
                    if len(new_keys) >= 4:
                        item['property_name'] = new_keys[-1]
                        item['target_name'] = new_keys[-3]
                        item['target_type'] = new_keys[-4]
                    items.append(item)
    return items

class FilterModule(object):
    """
    Custom Ansible filter module
    """
    def filters(self):
        return {
            'flatten_emcli_metrics': flatten_emcli_metrics
        }
