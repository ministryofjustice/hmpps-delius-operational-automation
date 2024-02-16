from ansible.errors import AnsibleFilterError

def flatten_custom_properties(d, parent_keys=list(), separator='_'):
    """
    A custom filter to flatten the combined_oem_metrics
    dictionary.  We assume the structure is:

    combined_oem_metrics:
         target_type:
            target_name:
                custom_properties:
                   <property name>: <property value>

    """
    items = []
    for k, v in d.items():
        new_keys = parent_keys + [k]
        if isinstance(v, dict):
            items.extend(flatten_custom_properties(v, new_keys, separator=separator))
        else:
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
            'flatten_custom_properties': flatten_custom_properties
        }
