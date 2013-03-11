{-# LANGUAGE FlexibleContexts #-}

module Cloud.AWS.EC2.AvailabilityZone
    ( describeAvailabilityZones
    ) where

import Data.Text (Text)

import Data.XML.Types (Event)
import Data.Conduit
import Control.Applicative

import Cloud.AWS.EC2.Internal
import Cloud.AWS.EC2.Types
import Cloud.AWS.EC2.Query
import Cloud.AWS.Lib.Parser

describeAvailabilityZones
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ ZoneNames
    -> [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m AvailabilityZone)
describeAvailabilityZones zones filters =
    ec2QuerySource "DescribeAvailabilityZones" params availabilityZoneInfo
  where
    params =
        [ "ZoneName" |.#= zones
        , filtersParam filters
        ]
    availabilityZoneInfo :: MonadThrow m
        => Conduit Event m AvailabilityZone
    availabilityZoneInfo = itemConduit "availabilityZoneInfo" $
        AvailabilityZone
        <$> getT "zoneName"
        <*> getT "zoneState"
        <*> getT "regionName"
        <*> itemsSet "messageSet" (getT "message")