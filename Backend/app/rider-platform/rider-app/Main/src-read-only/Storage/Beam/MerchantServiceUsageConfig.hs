{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Storage.Beam.MerchantServiceUsageConfig where

import qualified Database.Beam as B
import qualified Domain.Types.UtilsTH
import qualified Kernel.External.AadhaarVerification
import qualified Kernel.External.Call.Types
import Kernel.External.Encryption
import qualified Kernel.External.Maps.Types
import qualified Kernel.External.Notification.Types
import qualified Kernel.External.SMS.Types
import qualified Kernel.External.Ticket.Types
import qualified Kernel.External.Whatsapp.Types
import Kernel.Prelude
import qualified Kernel.Prelude
import Tools.Beam.UtilsTH

data MerchantServiceUsageConfigT f = MerchantServiceUsageConfigT
  { aadhaarVerificationService :: B.C f Kernel.External.AadhaarVerification.AadhaarVerificationService,
    autoComplete :: B.C f Kernel.External.Maps.Types.MapsService,
    createdAt :: B.C f Kernel.Prelude.UTCTime,
    enableDashboardSms :: B.C f Kernel.Prelude.Bool,
    getDistances :: B.C f Kernel.External.Maps.Types.MapsService,
    getDistancesForCancelRide :: B.C f Kernel.External.Maps.Types.MapsService,
    getExophone :: B.C f Kernel.External.Call.Types.CallService,
    getPickupRoutes :: B.C f Kernel.External.Maps.Types.MapsService,
    getPlaceDetails :: B.C f Kernel.External.Maps.Types.MapsService,
    getPlaceName :: B.C f Kernel.External.Maps.Types.MapsService,
    getRoutes :: B.C f Kernel.External.Maps.Types.MapsService,
    getTripRoutes :: B.C f Kernel.External.Maps.Types.MapsService,
    initiateCall :: B.C f Kernel.External.Call.Types.CallService,
    issueTicketService :: B.C f Kernel.External.Ticket.Types.IssueTicketService,
    merchantId :: B.C f Kernel.Prelude.Text,
    merchantOperatingCityId :: B.C f Kernel.Prelude.Text,
    notifyPerson :: B.C f Kernel.External.Notification.Types.NotificationService,
    smsProvidersPriorityList :: B.C f [Kernel.External.SMS.Types.SmsService],
    snapToRoad :: B.C f Kernel.External.Maps.Types.MapsService,
    updatedAt :: B.C f Kernel.Prelude.UTCTime,
    useFraudDetection :: B.C f Kernel.Prelude.Bool,
    whatsappProvidersPriorityList :: B.C f [Kernel.External.Whatsapp.Types.WhatsappService]
  }
  deriving (Generic, B.Beamable)

instance B.Table MerchantServiceUsageConfigT where
  data PrimaryKey MerchantServiceUsageConfigT f = MerchantServiceUsageConfigId (B.C f Kernel.Prelude.Text) deriving (Generic, B.Beamable)
  primaryKey = MerchantServiceUsageConfigId . merchantOperatingCityId

type MerchantServiceUsageConfig = MerchantServiceUsageConfigT Identity

$(enableKVPG ''MerchantServiceUsageConfigT ['merchantOperatingCityId] [])

$(mkTableInstances ''MerchantServiceUsageConfigT "merchant_service_usage_config")

$(Domain.Types.UtilsTH.mkCacParseInstance ''MerchantServiceUsageConfigT)
