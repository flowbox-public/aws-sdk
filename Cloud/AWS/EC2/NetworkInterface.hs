{-# LANGUAGE FlexibleContexts, RankNTypes #-}

module Cloud.AWS.EC2.NetworkInterface
    ( assignPrivateIpAddresses
    , unassignPrivateIpAddresses
    , describeNetworkInterfaces
    , createNetworkInterface
    , deleteNetworkInterface
    , attachNetworkInterface
    , detachNetworkInterface
    ) where

import Data.IP (IPv4)
import Data.Text (Text)
import Data.Conduit
import Control.Applicative

import Cloud.AWS.EC2.Internal
import Cloud.AWS.EC2.Types
import Cloud.AWS.EC2.Query
import Cloud.AWS.Lib.Parser.Unordered
import Cloud.AWS.Lib.ToText (toText)

assignPrivateIpAddresses
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ NetworkInterfaceId
    -> Either [IPv4] Int -- ^ PrivateIpAddresses or Count
    -> Maybe Bool
    -> EC2 m Bool
assignPrivateIpAddresses niid epip ar =
    ec2Query "AssignPrivateIpAddresses" params $ xmlParser (.< "return")
  where
    params =
        [ "NetworkInterfaceId" |= niid
        , either f g epip
        , "AllowReassignment" |=? ar
        ]
    f = ("PrivateIpAddress" |.#=)
    g = ("SecondaryPrivateIpAddressCount" |=)

unassignPrivateIpAddresses
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ NetworkInterfaceId
    -> [IPv4] -- ^ PrivateIpAddresses
    -> EC2 m Bool
unassignPrivateIpAddresses niid addrs =
    ec2Query "UnassignPrivateIpAddresses" params $ xmlParser (.< "return")
  where
    params =
        [ "NetworkInterfaceId" |= niid
        , "PrivateIpAddress" |.#= addrs
        ]

describeNetworkInterfaces
    :: (MonadBaseControl IO m, MonadResource m)
    => [Text] -- ^ NetworkInterfaceIds
    -> [Filter]
    -> EC2 m (ResumableSource m NetworkInterface)
describeNetworkInterfaces niid filters =
    ec2QuerySource "DescribeNetworkInterfaces" params
        $ itemConduit' "networkInterfaceSet" networkInterfaceConv
  where
    params =
        [ "NetworkInterfaceId" |.#= niid
        , filtersParam filters
        ]

networkInterfaceConv
    :: (MonadThrow m, Applicative m)
    => SimpleXML -> m NetworkInterface
networkInterfaceConv xml = NetworkInterface
    <$> xml .< "networkInterfaceId"
    <*> xml .< "subnetId"
    <*> xml .< "vpcId"
    <*> xml .< "availabilityZone"
    <*> xml .< "description"
    <*> xml .< "ownerId"
    <*> xml .< "requesterId"
    <*> xml .< "requesterManaged"
    <*> xml .< "status"
    <*> xml .< "macAddress"
    <*> xml .< "privateIpAddress"
    <*> xml .< "privateDnsName"
    <*> xml .< "sourceDestCheck"
    <*> groupSetConv xml
    <*> networkInterfaceAttachmentConv xml
    <*> networkInterfaceAssociationConv xml
    <*> resourceTagConv xml
    <*> itemsSet' xml "privateIpAddressesSet" (\xml' ->
        NetworkInterfacePrivateIpAddress
        <$> xml' .< "privateIpAddress"
        <*> xml' .< "privateDnsName"
        <*> xml' .< "primary"
        <*> networkInterfaceAssociationConv xml
        )

networkInterfaceAssociationConv
    :: (MonadThrow m, Applicative m)
    => SimpleXML -> m (Maybe NetworkInterfaceAssociation)
networkInterfaceAssociationConv xml = getElementM xml "association" $ \xml' ->
    NetworkInterfaceAssociation
    <$> xml' .< "attachmentId"
    <*> xml' .< "instanceId"
    <*> xml' .< "publicIp"
    <*> xml' .< "publicDnsName"
    <*> xml' .< "ipOwnerId"
    <*> xml' .< "associationId"

createNetworkInterface
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ The ID of the subnet to associate with the network interface.
    -> SecondaryPrivateIpAddressParam -- ^ The private IP address of the specified network interface.
    -> Maybe Text -- ^ The description of the network interface.
    -> [Text] -- ^ A list of security group IDs for use by the network interface.
    -> EC2 m NetworkInterface
createNetworkInterface subnet privateAddresses description securityGroupIds =
    ec2Query "CreateNetworkInterface" params $ xmlParser $ \xml ->
        getElement xml "networkInterface" networkInterfaceConv
  where
    params :: [QueryParam]
    params =
        [ "SubnetId" |= subnet
        , "Description" |=? description
        , "SecurityGroup" |.#= securityGroupIds
        ] ++ fromSecondary privateAddresses

    fromSecondary :: SecondaryPrivateIpAddressParam -> [QueryParam]
    fromSecondary SecondaryPrivateIpAddressParamNothing = []
    fromSecondary (SecondaryPrivateIpAddressParamCount n) = ["SecondaryPrivateIpAddressCount" |= n]
    fromSecondary (SecondaryPrivateIpAddressParamSpecified addrs primary) =
        [ "PrivateIpAddresses" |.#. map (\addr -> ["PrivateIpAddress" |= addr]) addrs
        , maybeParam $ primaryParam <$> primary
        ]

    primaryParam :: Int -> QueryParam
    primaryParam n = "PrivateIpAddresses" |.+ toText n |.+ "Primary" |= True

deleteNetworkInterface
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ The ID of the network interface.
    -> EC2 m Bool
deleteNetworkInterface networkInterface =
    ec2Query "DeleteNetworkInterface" ["NetworkInterfaceId" |= networkInterface] $
        xmlParser (.< "return")

attachNetworkInterface
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ The ID of the network interface to attach.
    -> Text -- ^ The ID of the instance to attach to the network interface.
    -> Int -- ^ The index of the device for the network interface attachment.
    -> EC2 m Text -- ^ The ID of the attachment.
attachNetworkInterface networkInterface inst deviceIdx =
    ec2Query "AttachNetworkInterface" params $ xmlParser (.< "attachmentId")
  where
    params =
        [ "NetworkInterfaceId" |= networkInterface
        , "InstanceId" |= inst
        , "DeviceIndex" |= deviceIdx
        ]

detachNetworkInterface
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ The ID of the attachment.
    -> Maybe Bool -- ^ Set to true to force a detachment.
    -> EC2 m Bool
detachNetworkInterface attachment force =
    ec2Query "DetachNetworkInterface" params $ xmlParser (.< "return")
  where
    params =
        [ "AttachmentId" |= attachment
        , "Force" |=? force
        ]
