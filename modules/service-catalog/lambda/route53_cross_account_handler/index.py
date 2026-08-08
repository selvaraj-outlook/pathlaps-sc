"""
CloudFormation custom-resource handler for cross-account Route 53 record
management (Option B - see terraform/modules/service-catalog/AGENTS.md).

Runs in the SharedServices hub account. Invoked by a Custom::Route53Record
resource in a CloudFormation stack running in ANOTHER account (e.g. Account
A), via the cross-account resource-based permission granted in
cross-account-dns.tf (aws_lambda_permission, one per allowed invoker
principal). That permission controls WHO can invoke this function at all;
ALLOWED_HOSTED_ZONE_IDS below is a second, independent layer that controls
WHICH zone this function is willing to touch regardless of what a caller
puts in ResourceProperties - keep both in sync with the
StandardRoute53RecordProduct statement's Resource list in constraints.tf,
they are declared separately from that statement on purpose (this Lambda
has its own IAM execution role, not the shared launch role).
"""

import json
import urllib.request

import boto3

route53 = boto3.client("route53")

# Must match the hosted zone ARN(s) allowlisted in constraints.tf's
# StandardRoute53RecordProduct statement, and this function's own IAM
# execution role policy (route53_cross_account_handler_permissions in
# cross-account-dns.tf). Kept as a literal here (not imported from
# Terraform) because this file is packaged and deployed independently of
# the .tf files - update all three places together.
ALLOWED_HOSTED_ZONE_IDS = {"Z048880320A4YLK98LLYY"}


def handler(event, context):
    request_type = event["RequestType"]
    props = event["ResourceProperties"]
    hosted_zone_id = props["HostedZoneId"]
    record_name = props["RecordName"]
    record_type = props["RecordType"]
    physical_resource_id = event.get("PhysicalResourceId") or f"{record_name}-{record_type}"

    try:
        if hosted_zone_id not in ALLOWED_HOSTED_ZONE_IDS:
            raise ValueError(f"Hosted zone {hosted_zone_id} is not in the allowlist")

        record_set = {
            "Name": record_name,
            "Type": record_type,
            "TTL": int(props.get("Ttl", 300)),
            "ResourceRecords": [{"Value": props["RecordValue"]}],
        }

        if request_type in ("Create", "Update"):
            route53.change_resource_record_sets(
                HostedZoneId=hosted_zone_id,
                ChangeBatch={"Changes": [{"Action": "UPSERT", "ResourceRecordSet": record_set}]},
            )
        elif request_type == "Delete":
            try:
                route53.change_resource_record_sets(
                    HostedZoneId=hosted_zone_id,
                    ChangeBatch={"Changes": [{"Action": "DELETE", "ResourceRecordSet": record_set}]},
                )
            except route53.exceptions.InvalidChangeBatch:
                # Record already gone (or never matched exactly) - deletes
                # must be idempotent so a Delete on a stack that never fully
                # created doesn't strand the CFN stack in DELETE_FAILED.
                pass

        _send_response(event, context, "SUCCESS", physical_resource_id, {"RecordFqdn": record_name})
    except Exception as exc:  # noqa: BLE001 - must always send a CFN response, success or failure
        _send_response(event, context, "FAILED", physical_resource_id, {}, reason=str(exc))


def _send_response(event, context, status, physical_resource_id, data, reason=None):
    body = json.dumps(
        {
            "Status": status,
            "Reason": reason or f"See CloudWatch Logs: {context.log_stream_name}",
            "PhysicalResourceId": physical_resource_id,
            "StackId": event["StackId"],
            "RequestId": event["RequestId"],
            "LogicalResourceId": event["LogicalResourceId"],
            "Data": data,
            "NoEcho": False,
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        url=event["ResponseURL"],
        data=body,
        method="PUT",
        headers={"Content-Type": "", "Content-Length": str(len(body))},
    )
    urllib.request.urlopen(request)  # noqa: S310 - ResponseURL is an AWS-issued presigned S3 URL
