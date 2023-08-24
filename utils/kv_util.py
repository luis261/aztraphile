import logging
import os


def is_faulty_kv_ref(secret_val):
    unresolved_ref_indicators = ["@Microsoft.KeyVault", "(SecretUri=", ".vault.azure.net/secrets"]
    return any(s in secret_val for s in unresolved_ref_indicators)

def read_secret_via_appsetting(appsetting_key, verbose=False):
    try:
        secret_val = os.environ[appsetting_key]
    except KeyError:
        err_info = f"There is no variable with name \"{appsetting_key}\" configured in the appsettings."
        if verbose:
            logging.error(err_info)
        raise KeyError(err_info)

    if not is_faulty_kv_ref(secret_val):
        if verbose:
            logging.warning(f"The resolved secret value of \"{appsetting_key}\" is \"{secret_val}\".")
        return secret_val
    else:
        err_info = f"The value retrieved from the appsettings under \"{appsetting_key}\" contains signatures indicating an unresolved secret."
        if verbose:
            logging.warning(err_info)
            logging.warning(f"The value of \"{appsetting_key}\" is \"{secret_val}\".")
        raise ValueError(err_info)
