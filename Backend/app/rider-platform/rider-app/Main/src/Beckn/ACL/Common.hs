{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Beckn.ACL.Common where

import qualified Beckn.OnDemand.Utils.Common as Utils
import qualified Beckn.Types.Core.Taxi.Common.CancellationSource as Common
import qualified Beckn.Types.Core.Taxi.Common.Payment as Payment
import qualified Beckn.Types.Core.Taxi.Search as Search
import qualified BecknV2.OnDemand.Tags as Tag
import qualified BecknV2.OnDemand.Types as Spec
import qualified BecknV2.OnDemand.Utils.Common as Utils
import qualified Data.Text as T
import Domain.Action.Beckn.Common as Common
import qualified Domain.Action.UI.Search as DSearch
import qualified Domain.Types.BookingCancellationReason as SBCR
import qualified Domain.Types.MerchantPaymentMethod as DMPM
import Kernel.External.Maps.Types as Maps
import Kernel.Prelude
import qualified Kernel.Storage.Hedis as Hedis
import qualified Kernel.Types.Beckn.DecimalValue as DecimalValue
import Kernel.Types.Id
import Kernel.Utils.Common
import Tools.Error

validatePrices :: (MonadThrow m, Log m, Num a, Ord a) => a -> a -> m ()
validatePrices price priceWithDiscount = do
  when (price < 0) $ throwError $ InvalidRequest "price is less than zero"
  when (priceWithDiscount < 0) $ throwError $ InvalidRequest "discounted price is less than zero"
  when (priceWithDiscount > price) $ throwError $ InvalidRequest "price is lesser than discounted price"

castDPaymentCollector :: DMPM.PaymentCollector -> Payment.PaymentCollector
castDPaymentCollector DMPM.BAP = Payment.BAP
castDPaymentCollector DMPM.BPP = Payment.BPP

castDPaymentType :: DMPM.PaymentType -> Payment.PaymentType
castDPaymentType DMPM.ON_FULFILLMENT = Payment.ON_FULFILLMENT
castDPaymentType DMPM.POSTPAID = Payment.ON_FULFILLMENT

castDPaymentInstrument :: DMPM.PaymentInstrument -> Payment.PaymentInstrument
castDPaymentInstrument (DMPM.Card DMPM.DefaultCardType) = Payment.Card Payment.DefaultCardType
castDPaymentInstrument (DMPM.Wallet DMPM.DefaultWalletType) = Payment.Wallet Payment.DefaultWalletType
castDPaymentInstrument DMPM.UPI = Payment.UPI
castDPaymentInstrument DMPM.NetBanking = Payment.NetBanking
castDPaymentInstrument DMPM.Cash = Payment.Cash

castPaymentCollector :: Payment.PaymentCollector -> DMPM.PaymentCollector
castPaymentCollector Payment.BAP = DMPM.BAP
castPaymentCollector Payment.BPP = DMPM.BPP

castPaymentType :: Payment.PaymentType -> DMPM.PaymentType
castPaymentType Payment.ON_FULFILLMENT = DMPM.ON_FULFILLMENT
castPaymentType Payment.POSTPAID = DMPM.ON_FULFILLMENT

castPaymentInstrument :: Payment.PaymentInstrument -> DMPM.PaymentInstrument
castPaymentInstrument (Payment.Card Payment.DefaultCardType) = DMPM.Card DMPM.DefaultCardType
castPaymentInstrument (Payment.Wallet Payment.DefaultWalletType) = DMPM.Wallet DMPM.DefaultWalletType
castPaymentInstrument Payment.UPI = DMPM.UPI
castPaymentInstrument Payment.NetBanking = DMPM.NetBanking
castPaymentInstrument Payment.Cash = DMPM.Cash

mkLocation :: DSearch.SearchReqLocation -> Search.Location
mkLocation info =
  Search.Location
    { gps =
        Search.Gps
          { lat = info.gps.lat,
            lon = info.gps.lon
          },
      address =
        Just
          Search.Address
            { locality = info.address.area,
              state = info.address.state,
              country = info.address.country,
              building = info.address.building,
              street = info.address.street,
              city = info.address.city,
              area_code = info.address.areaCode,
              door = info.address.door,
              ward = info.address.ward
            }
    }

castCancellationSource :: Common.CancellationSource -> SBCR.CancellationSource
castCancellationSource = \case
  Common.ByUser -> SBCR.ByUser
  Common.ByDriver -> SBCR.ByDriver
  Common.ByMerchant -> SBCR.ByMerchant
  Common.ByAllocator -> SBCR.ByAllocator
  Common.ByApplication -> SBCR.ByApplication

getTagV2' :: Tag.TagGroup -> Tag.Tag -> Maybe [Spec.TagGroup] -> Maybe Text
getTagV2' tagGroupCode tagCode mbTagGroups =
  case mbTagGroups of
    Just tagGroups -> getTagV2 tagGroupCode tagCode tagGroups
    Nothing -> Nothing

getTagV2 :: Tag.TagGroup -> Tag.Tag -> [Spec.TagGroup] -> Maybe Text
getTagV2 tagGroupCode tagCode tagGroups = do
  tagGroup <- find (\tagGroup -> descriptorCode tagGroup.tagGroupDescriptor == Just (show tagGroupCode)) tagGroups
  case tagGroup.tagGroupList of
    Nothing -> Nothing
    Just tagGroupList -> do
      tag <- find (\tag -> descriptorCode tag.tagDescriptor == Just (show tagCode)) tagGroupList
      tag.tagValue
  where
    descriptorCode :: Maybe Spec.Descriptor -> Maybe Text
    descriptorCode (Just desc) = desc.descriptorCode
    descriptorCode Nothing = Nothing

parseBookingDetails :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> m Common.BookingDetails
parseBookingDetails order msgId = do
  bppBookingId <- order.orderId & fromMaybeM (InvalidRequest "order_id is not present in RideAssigned Event.")
  isInitiatedByCronJob <- (\(val :: Maybe Bool) -> isJust val) <$> Hedis.safeGet (makeContextMessageIdStatusSyncKey msgId)
  bppRideId <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentId) & fromMaybeM (InvalidRequest "fulfillment_id is not present in RideAssigned Event.")
  stops <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentStops) & fromMaybeM (InvalidRequest "fulfillment_stops is not present in RideAssigned Event.")
  start <- Utils.getStartLocation stops & fromMaybeM (InvalidRequest "pickup stop is not present in RideAssigned Event.")
  otp <- start.stopAuthorization >>= (.authorizationToken) & fromMaybeM (InvalidRequest "authorization_token is not present in RideAssigned Event.")
  driverName <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personName) & fromMaybeM (InvalidRequest "driverName is not present in RideAssigned Event.")
  driverMobileNumber <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentContact) >>= (.contactPhone) & fromMaybeM (InvalidRequest "driverMobileNumber is not present in RideAssigned Event.")
  let tagGroups = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personTags)
  let rating :: Maybe HighPrecMeters = readMaybe . T.unpack =<< getTagV2' Tag.DRIVER_DETAILS Tag.RATING tagGroups
      registeredAt :: Maybe UTCTime = readMaybe . T.unpack =<< getTagV2' Tag.DRIVER_DETAILS Tag.REGISTERED_AT tagGroups
  let driverImage = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personImage) >>= (.imageUrl)
  let vehicleColor = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentVehicle) >>= (.vehicleColor)
  vehicleModel <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentVehicle) >>= (.vehicleModel) & fromMaybeM (InvalidRequest "vehicleModel is not present in RideAssigned Event.")
  vehicleNumber <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentVehicle) >>= (.vehicleRegistration) & fromMaybeM (InvalidRequest "vehicleNumber is not present in RideAssigned Event.")
  pure $
    Common.BookingDetails
      { bppBookingId = Id bppBookingId,
        bppRideId = Id bppRideId,
        driverMobileCountryCode = Just "+91", -----------TODO needs to be added in agent Tags------------
        driverRating = realToFrac <$> rating,
        driverRegisteredAt = registeredAt,
        ..
      }

parseRideAssignedEvent :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> Text -> m Common.RideAssignedReq
parseRideAssignedEvent order msgId txnId = do
  let tagGroups = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personTags)
  let castToBool mbVar = case T.toLower <$> mbVar of
        Just "true" -> True
        _ -> False
  let isDriverBirthDay = castToBool $ getTagV2' Tag.DRIVER_DETAILS Tag.IS_DRIVER_BIRTHDAY tagGroups
      isFreeRide = castToBool $ getTagV2' Tag.DRIVER_DETAILS Tag.IS_FREE_RIDE tagGroups
  bookingDetails <- parseBookingDetails order msgId
  return
    Common.RideAssignedReq
      { bookingDetails,
        transactionId = txnId,
        isDriverBirthDay,
        isFreeRide
      }

parseRideStartedEvent :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> m Common.RideStartedReq
parseRideStartedEvent order msgId = do
  bookingDetails <- parseBookingDetails order msgId
  stops <- order.orderFulfillments >>= listToMaybe >>= (.fulfillmentStops) & fromMaybeM (InvalidRequest "fulfillment_stops is not present in RideStarted Event.")
  start <- Utils.getStartLocation stops & fromMaybeM (InvalidRequest "pickup stop is not present in RideStarted Event.")
  let rideStartTime = start.stopTime >>= (.timeTimestamp)
      personTagsGroup = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personTags)
      tagGroups = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentTags)
      startOdometerReading = readMaybe . T.unpack =<< getTagV2' Tag.RIDE_ODOMETER_DETAILS Tag.START_ODOMETER_READING tagGroups
      tripStartLocation = getLocationFromTagV2 personTagsGroup Tag.CURRENT_LOCATION Tag.CURRENT_LOCATION_LAT Tag.CURRENT_LOCATION_LON
      driverArrivalTime :: Maybe UTCTime = readMaybe . T.unpack =<< getTagV2' Tag.DRIVER_ARRIVED_INFO Tag.ARRIVAL_TIME tagGroups
  pure $
    Common.RideStartedReq
      { bookingDetails,
        endOtp_ = Just bookingDetails.otp,
        startOdometerReading,
        ..
      }

getLocationFromTagV2 :: Maybe [Spec.TagGroup] -> Tag.TagGroup -> Tag.Tag -> Tag.Tag -> Maybe Maps.LatLong
getLocationFromTagV2 tagGroup key latKey lonKey =
  let tripStartLat :: Maybe Double = readMaybe . T.unpack =<< getTagV2' key latKey tagGroup
      tripStartLon :: Maybe Double = readMaybe . T.unpack =<< getTagV2' key lonKey tagGroup
   in Maps.LatLong <$> tripStartLat <*> tripStartLon

parseDriverArrivedEvent :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> m Common.DriverArrivedReq
parseDriverArrivedEvent order msgId = do
  bookingDetails <- parseBookingDetails order msgId
  let tagGroups = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentTags)
      arrivalTime = readMaybe . T.unpack =<< getTagV2' Tag.DRIVER_ARRIVED_INFO Tag.ARRIVAL_TIME tagGroups
  return $
    Common.DriverArrivedReq
      { bookingDetails,
        arrivalTime
      }

parseRideCompletedEvent :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> m Common.RideCompletedReq
parseRideCompletedEvent order msgId = do
  bookingDetails <- parseBookingDetails order msgId
  currency :: Currency <- order.orderQuote >>= (.quotationPrice) >>= (.priceCurrency) >>= (readMaybe . T.unpack) & fromMaybeM (InvalidRequest "quote.price.currency is not present in RideCompleted Event.")
  fare :: DecimalValue.DecimalValue <- order.orderQuote >>= (.quotationPrice) >>= (.priceValue) >>= DecimalValue.valueFromString & fromMaybeM (InvalidRequest "quote.price.value is not present in RideCompleted Event.")
  let totalFare = fare
      tagGroups = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentTags)
      chargeableDistance :: Maybe Distance = (highPrecMetersToDistance <$>) $ readMaybe . T.unpack =<< getTagV2' Tag.RIDE_DISTANCE_DETAILS Tag.CHARGEABLE_DISTANCE tagGroups
      traveledDistance :: Maybe Distance = (highPrecMetersToDistance <$>) $ readMaybe . T.unpack =<< getTagV2' Tag.RIDE_DISTANCE_DETAILS Tag.TRAVELED_DISTANCE tagGroups
      endOdometerReading = readMaybe . T.unpack =<< getTagV2' Tag.RIDE_DISTANCE_DETAILS Tag.END_ODOMETER_READING tagGroups
  fareBreakups' <- order.orderQuote >>= (.quotationBreakup) & fromMaybeM (InvalidRequest "quote breakup is not present in RideCompleted Event.")
  fareBreakups <- traverse mkDFareBreakup fareBreakups'
  let personTagsGroup = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentAgent) >>= (.agentPerson) >>= (.personTags)
      tripEndLocation = getLocationFromTagV2 personTagsGroup Tag.CURRENT_LOCATION Tag.CURRENT_LOCATION_LAT Tag.CURRENT_LOCATION_LON
      rideEndTime = order.orderFulfillments >>= listToMaybe >>= (.fulfillmentStops) >>= Utils.getDropLocation >>= (.stopTime) >>= (.timeTimestamp)
      paymentStatus = order.orderPayments >>= listToMaybe >>= (.paymentStatus) >>= readMaybe . T.unpack
  pure $
    Common.RideCompletedReq
      { bookingDetails,
        fare = Utils.decimalValueToPrice currency fare,
        totalFare = Utils.decimalValueToPrice currency totalFare,
        chargeableDistance,
        traveledDistance,
        fareBreakups,
        paymentUrl = Nothing,
        ..
      }
  where
    mkDFareBreakup breakup = do
      val :: DecimalValue.DecimalValue <- breakup.quotationBreakupInnerPrice >>= (.priceValue) >>= DecimalValue.valueFromString & fromMaybeM (InvalidRequest "quote.breakup.price.value is not present in RideCompleted Event.")
      currency :: Currency <- breakup.quotationBreakupInnerPrice >>= (.priceCurrency) >>= readMaybe . T.unpack & fromMaybeM (InvalidRequest "quote.breakup.price.currency is not present in RideCompleted Event.")
      title <- breakup.quotationBreakupInnerTitle & fromMaybeM (InvalidRequest "breakup_title is not present in RideCompleted Event.")
      pure $
        Common.DFareBreakup
          { amount = Utils.decimalValueToPrice currency val,
            description = title
          }

parseBookingCancelledEvent :: (MonadFlow m, CacheFlow m r) => Spec.Order -> Text -> m Common.BookingCancelledReq
parseBookingCancelledEvent order msgId = do
  bppBookingId <- order.orderId & fromMaybeM (InvalidRequest "order_id is not present in BookingCancelled Event.")
  bookingDetails <-
    case order.orderFulfillments of
      Just _ -> Just <$> parseBookingDetails order msgId
      Nothing -> pure Nothing
  cancellationSource <- order.orderCancellation >>= (.cancellationCancelledBy) & fromMaybeM (InvalidRequest "cancellationSource is not present in BookingCancelled Event.")
  return $
    Common.BookingCancelledReq
      { bppBookingId = Id bppBookingId,
        bookingDetails,
        cancellationSource = Utils.castCancellationSourceV2 cancellationSource
      }

makeContextMessageIdStatusSyncKey :: Text -> Text
makeContextMessageIdStatusSyncKey msgId = "SyncAPI:Ride:Cron:Status:MessageId" <> msgId
