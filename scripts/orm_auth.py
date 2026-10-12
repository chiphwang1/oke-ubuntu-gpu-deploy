"""Use the ORM runner's delegated identity, matching the OCI Terraform provider.

Tokens remain in memory; never add them to arguments, outputs, or Terraform state.
"""
import os
from pathlib import Path


def provider_env(name):
    # Same precedence as oracle/terraform-provider-oci internal/utils/helpers.go.
    return next((os.environ[k] for k in ("TF_VAR_" + name, "OCI_" + name, name, "OCI_" + name.upper()) if os.environ.get(k)), "")


def uses_delegation():
    flag = provider_env("use_obo_token")
    enabled = flag.lower() in ("1", "t", "true") if flag else bool(provider_env("obo_token_path") or provider_env("obo_token"))
    return os.environ.get("OCI_CLI_AUTH") in ("resource_principal", "instance_principal") and enabled


def delegation_token():
    path = provider_env("obo_token_path")
    token = Path(path).read_text().strip() if path else provider_env("obo_token").strip()
    # Some ORM runners advertise a generic CLI token path that does not exist.
    # Prefer the provider's actual inline token before consulting that fallback.
    if not token and os.environ.get("OCI_DELEGATION_TOKEN_FILE"):
        token = Path(os.environ["OCI_DELEGATION_TOKEN_FILE"]).read_text().strip()
    if not token:
        raise RuntimeError("ORM delegation is enabled but its token is unavailable")
    return token


def client():
    import oci
    from oci.auth.signers import EphemeralResourcePrincipalSigner

    if os.environ.get("OCI_CLI_AUTH") == "instance_principal":
        signer = oci.auth.signers.InstancePrincipalsDelegationTokenSigner(delegation_token=delegation_token())
        return oci.container_engine.ContainerEngineClient(
            {"region": os.environ["OCI_CLI_REGION"]}, signer=signer,
            retry_strategy=oci.retry.DEFAULT_RETRY_STRATEGY,
        )

    if os.environ.get("OCI_RESOURCE_PRINCIPAL_VERSION") != "2.2":
        raise RuntimeError("ORM delegated authentication currently requires Resource Principal version 2.2")

    class OrmSigner(EphemeralResourcePrincipalSigner):
        def __call__(self, request, enforce_content_headers=True):
            request.headers["opc-obo-token"] = delegation_token()
            return super().__call__(request, enforce_content_headers=enforce_content_headers)

    signer = OrmSigner(
        session_token=os.environ.get("OCI_RESOURCE_PRINCIPAL_RPST"),
        private_key=os.environ.get("OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM"),
        private_key_passphrase=os.environ.get("OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM_PASSPHRASE"),
        region=os.environ.get("OCI_CLI_REGION"),
        generic_headers=["date", "(request-target)", "host", "opc-obo-token"],
    )
    return oci.container_engine.ContainerEngineClient(
        {"region": os.environ["OCI_CLI_REGION"]}, signer=signer,
        retry_strategy=oci.retry.DEFAULT_RETRY_STRATEGY,
    )
