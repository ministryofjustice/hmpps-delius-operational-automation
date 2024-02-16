from ansible.errors import AnsibleFilterError

def flatten_metrics(d, parent_keys=list(), separator='_'):
    """
    A custom filter to flatten the combined_oem_metrics
    dictionary.  We assume the structure is:

    combined_oem_metrics:
         target_type:
            target_name:
                input_file:

    """
    items = []
    for k, v in d.items():
        new_keys = parent_keys + [k]
        if isinstance(v, dict):
            items.extend(flatten_metrics(v, new_keys, separator=separator))
        else:
            item = {'target_type': None, 'target_name': None, 'input_file': v}
            if len(new_keys) >= 3:
                item['target_name'] = new_keys[-2]
                item['target_type'] = new_keys[-3]
            items.append(item)
    return items

class FilterModule(object):
    """
    Custom Ansible filter module
    """
    def filters(self):
        return {
            'flatten_metrics': flatten_metrics
        }
