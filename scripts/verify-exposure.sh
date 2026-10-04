#!/usr/bin/env bash
# Asserts the intended exposure model. Exits non-zero if anything is exposed that should not be.
# Usage: scripts/verify-exposure.sh [backend-nlb-hostname]
#   With a hostname, also checks that the backend NLB is unreachable from where this runs (the internet).
set -uo pipefail

fail=0
ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; fail=1; }

vpc_id() { aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$1" --query 'Vpcs[0].VpcId' --output text; }
GW_VPC="$(vpc_id vpc-gateway)"
BE_VPC="$(vpc_id vpc-backend)"
echo "gateway VPC: $GW_VPC, backend VPC: $BE_VPC"

# 1. Load balancer schemes: backend internal, gateway internet-facing.
be_schemes="$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$BE_VPC'].Scheme" --output text)"
gw_schemes="$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$GW_VPC'].Scheme" --output text)"
[[ -n "$be_schemes" && "$be_schemes" != *internet-facing* ]] && ok "backend load balancer(s) are internal ($be_schemes)" || bad "backend load balancer is not internal: '$be_schemes'"
[[ "$gw_schemes" == *internet-facing* ]] && ok "gateway load balancer is internet-facing" || bad "gateway load balancer is not internet-facing: '$gw_schemes'"

# 2. No security group in the backend VPC accepts traffic from the whole internet.
sgs="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$BE_VPC" --query 'SecurityGroups[].GroupId' --output text | tr '\t' ',')"
open="$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sgs" \
  --query 'SecurityGroupRules[?IsEgress==`false` && (CidrIpv4==`0.0.0.0/0` || CidrIpv6==`::/0`)].GroupId' --output text)"
[[ -z "$open" ]] && ok "no backend security group allows inbound from 0.0.0.0/0 or ::/0" || bad "open inbound rule in: $open"

# 3. The backend NodePort is reachable only from the gateway VPC CIDR (plus the NLB health checks from its own subnets).
client_cidrs="$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sgs" \
  --query 'SecurityGroupRules[?IsEgress==`false` && Description!=`null` && starts_with(Description, `kubernetes.io/rule/nlb/client=`)].CidrIpv4' --output text)"
[[ "$client_cidrs" == "10.10.0.0/16" ]] && ok "NLB client rule allows only 10.10.0.0/16" || bad "NLB client rule CIDRs: '$client_cidrs'"

# 4. No instance in either VPC has a public IP.
public="$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$GW_VPC,$BE_VPC" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[?PublicIpAddress!=`null`].InstanceId' --output text)"
[[ -z "$public" ]] && ok "no running instance has a public IP" || bad "instances with public IP: $public"

# 5. From here (outside the VPCs) the backend NLB must not answer.
if [[ -n "${1:-}" ]]; then
  if curl -s -m 8 -o /dev/null "http://$1/"; then bad "backend NLB $1 answered from outside the VPC"; else ok "backend NLB does not answer from outside the VPC"; fi
fi

exit $fail
