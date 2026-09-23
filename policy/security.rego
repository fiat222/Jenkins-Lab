package taskflow.security

import rego.v1

deny contains message if {
    input.metadata.vulnerabilities.critical > 0
    message := sprintf(
        "Critical vulnerabilities found: %d",
        [input.metadata.vulnerabilities.critical],
    )
}

allow if {
    input.metadata.vulnerabilities.critical == 0
}