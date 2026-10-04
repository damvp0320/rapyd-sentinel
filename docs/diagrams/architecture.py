"""Renders docs/assets/architecture.png.

Every box and arrow below is declared explicitly, so the picture cannot drift from what is written here.
Regenerate with:
    pip install diagrams && brew install graphviz
    python docs/diagrams/architecture.py
"""
from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.network import NATGateway, NLB, VPCPeering, InternetGateway
from diagrams.k8s.compute import Pod
from diagrams.onprem.client import Users
from diagrams.onprem.network import Internet

BACKEND_VPC_LABEL = "vpc-backend (10.20.0.0/16)"
BACKEND_VPC = "cluster_" + BACKEND_VPC_LABEL
OUT = Path(__file__).resolve().parent.parent / "assets" / "architecture"

VPC = {"bgcolor": "#FFFFFF", "pencolor": "#8C4FFF", "penwidth": "2", "style": "rounded", "fontsize": "18", "labeljust": "l", "margin": "16"}
PUBLIC = {"bgcolor": "#F2F8E8", "pencolor": "#7AA116", "penwidth": "2", "style": "dashed,rounded", "fontsize": "13", "labeljust": "l"}
PRIVATE = {"bgcolor": "#E8F3FA", "pencolor": "#147EBA", "penwidth": "2", "style": "dashed,rounded", "fontsize": "13", "labeljust": "l"}
CLUSTER = {"bgcolor": "#F3EBFF", "pencolor": "#7B3FE4", "penwidth": "2", "style": "rounded", "fontsize": "14", "labeljust": "l"}

PATH = {"color": "#1565C0", "penwidth": "3", "fontcolor": "#1565C0", "fontsize": "18"}
EGRESS = {"color": "#888888", "style": "dashed", "penwidth": "1.5", "fontcolor": "#888888", "fontsize": "11"}
BLOCKED = {"color": "#D13212", "style": "dashed", "penwidth": "2.5", "fontcolor": "#D13212", "fontsize": "13"}

with Diagram(
    "Rapyd Sentinel – Architecture (AWS eu-west-3, Paris)",
    filename=str(OUT), outformat="png", show=False, direction="LR",
    graph_attr={"fontsize": "24", "labelloc": "t", "pad": "0.5", "nodesep": "0.6", "ranksep": "1.1", "splines": "spline", "dpi": "150", "bgcolor": "white", "compound": "true"},
    node_attr={"fontsize": "13"},
):
    clients = Users("Clients")
    internet = Internet("Internet")
    clients >> internet

    # ------------------------------------------------------------------ vpc-gateway
    with Cluster("vpc-gateway (10.10.0.0/16)", graph_attr=VPC):
        gw_igw = InternetGateway("Internet Gateway")
        with Cluster("Public subnet · AZ-b (10.10.2.0/24)", graph_attr=PUBLIC):
            gw_nat_b = NATGateway("NAT Gateway")
        with Cluster("Public subnet · AZ-a (10.10.1.0/24)", graph_attr=PUBLIC):
            gw_nat_a = NATGateway("NAT Gateway")
        pub_nlb = NLB("Public Load Balancer\n(NLB, internet-facing)")

        with Cluster("EKS cluster: eks-gateway", graph_attr=CLUSTER):
            with Cluster("Private subnet · AZ-b (10.10.12.0/24)", graph_attr=PRIVATE):
                gw_pod_b = Pod("NGINX proxy")
            with Cluster("Private subnet · AZ-a (10.10.11.0/24)", graph_attr=PRIVATE):
                gw_pod_a = Pod("NGINX proxy")

    # ------------------------------------------------------------------ peering
    peering = VPCPeering("VPC Peering\n(private traffic only)")

    # ------------------------------------------------------------------ vpc-backend
    with Cluster(BACKEND_VPC_LABEL, graph_attr=VPC):
        bk_igw = InternetGateway("Internet Gateway\n(outbound only, via NAT)")
        with Cluster("Public subnet · AZ-b (10.20.2.0/24)", graph_attr=PUBLIC):
            bk_nat_b = NATGateway("NAT Gateway")
        with Cluster("Public subnet · AZ-a (10.20.1.0/24)", graph_attr=PUBLIC):
            bk_nat_a = NATGateway("NAT Gateway")
        int_nlb = NLB("Internal Load Balancer\n(NLB, private IPs only)")

        with Cluster("EKS cluster: eks-backend", graph_attr=CLUSTER):
            with Cluster("Private subnet · AZ-b (10.20.12.0/24)", graph_attr=PRIVATE):
                bk_pod_b = Pod("Backend app")
            with Cluster("Private subnet · AZ-a (10.20.11.0/24)", graph_attr=PRIVATE):
                bk_pod_a = Pod("Backend app")

    # ------------------------------------------------------------------ request path 1 -> 4
    internet >> Edge(label=" 1 ", **PATH) >> gw_igw
    gw_igw >> Edge(**PATH) >> pub_nlb
    pub_nlb >> Edge(label=" 2 ", **PATH) >> gw_pod_a
    pub_nlb >> Edge(label=" 2 ", **PATH) >> gw_pod_b
    gw_pod_a >> Edge(label=" 3 ", **PATH) >> peering
    gw_pod_b >> Edge(label=" 3 ", **PATH) >> peering
    peering >> Edge(label=" 3 ", **PATH) >> int_nlb
    int_nlb >> Edge(label=" 4 ", **PATH) >> bk_pod_a
    int_nlb >> Edge(label=" 4 ", **PATH) >> bk_pod_b

    # ------------------------------------------------------------------ outbound only (NAT -> IGW -> Internet)
    gw_nat_a >> Edge(constraint="false", **EGRESS) >> gw_igw
    gw_nat_b >> Edge(constraint="false", **EGRESS) >> gw_igw
    bk_nat_a >> Edge(constraint="false", **EGRESS) >> bk_igw
    bk_nat_b >> Edge(constraint="false", **EGRESS) >> bk_igw
    bk_igw >> Edge(constraint="false", **EGRESS) >> internet

    # ------------------------------------------------------------------ blocked
    # Drawn from the Internet to the backend VPC border (lhead), and it stops there: nothing enters the VPC.
    internet >> Edge(label=" ✖ no direct access ", lhead=BACKEND_VPC, constraint="false", **BLOCKED) >> int_nlb
