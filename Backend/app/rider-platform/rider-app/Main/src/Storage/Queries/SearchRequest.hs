{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Storage.Queries.SearchRequest where

import Data.Text (strip)
import qualified Domain.Types.LocationMapping as DLM
import Domain.Types.Merchant.MerchantPaymentMethod (MerchantPaymentMethod)
import qualified Domain.Types.Merchant.MerchantPaymentMethod as DMPM
import Domain.Types.Person (Person)
import Domain.Types.SearchRequest
import EulerHS.Prelude (whenNothingM_)
import Kernel.Beam.Functions
import Kernel.Prelude
import Kernel.Types.Common
import Kernel.Types.Id
import Kernel.Utils.Common
import Kernel.Utils.Version
import qualified Sequelize as Se
import qualified SharedLogic.LocationMapping as SLM
import qualified Storage.Beam.SearchRequest as BeamSR
import qualified Storage.CachedQueries.Merchant as CQM
import qualified Storage.Queries.Location as QL
import qualified Storage.Queries.LocationMapping as QLM
import Tools.Error

createDSReq' :: (MonadFlow m, EsqDBFlow m r) => SearchRequest -> m ()
createDSReq' = createWithKV

create :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => SearchRequest -> m ()
create dsReq = do
  _ <- whenNothingM_ (QL.findById dsReq.fromLocation.id) $ do QL.create dsReq.fromLocation
  _ <- whenJust dsReq.toLocation $ \location -> processLocation location
  createDSReq' dsReq
  where
    processLocation location = whenNothingM_ (QL.findById location.id) $ do QL.create location

createDSReq :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => SearchRequest -> m ()
createDSReq searchRequest = do
  fromLocationMap <- SLM.buildPickUpLocationMapping searchRequest.fromLocation.id searchRequest.id.getId DLM.SEARCH_REQUEST (Just searchRequest.merchantId) (Just searchRequest.merchantOperatingCityId)
  mbToLocationMap <- maybe (pure Nothing) (\detail -> Just <$> SLM.buildDropLocationMapping detail.id searchRequest.id.getId DLM.SEARCH_REQUEST (Just searchRequest.merchantId) (Just searchRequest.merchantOperatingCityId)) searchRequest.toLocation
  void $ QLM.create fromLocationMap
  void $ whenJust mbToLocationMap $ \toLocMap -> QLM.create toLocMap
  create searchRequest

findById :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id SearchRequest -> m (Maybe SearchRequest)
findById (Id searchRequestId) = findOneWithKV [Se.Is BeamSR.id $ Se.Eq searchRequestId]

findByPersonId :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> Id SearchRequest -> m (Maybe SearchRequest)
findByPersonId (Id personId) (Id searchRequestId) = findOneWithKV [Se.And [Se.Is BeamSR.id $ Se.Eq searchRequestId, Se.Is BeamSR.riderId $ Se.Eq personId]]

findAllByPerson :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> m [SearchRequest]
findAllByPerson (Id personId) = findAllWithKV [Se.Is BeamSR.riderId $ Se.Eq personId]

findLatestSearchRequest :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> m (Maybe SearchRequest)
findLatestSearchRequest (Id riderId) = findAllWithOptionsKV [Se.Is BeamSR.riderId $ Se.Eq riderId] (Se.Desc BeamSR.createdAt) (Just 1) Nothing <&> listToMaybe

updateCustomerExtraFeeAndPaymentMethod :: (MonadFlow m, EsqDBFlow m r) => Id SearchRequest -> Maybe Price -> Maybe (Id DMPM.MerchantPaymentMethod) -> m ()
updateCustomerExtraFeeAndPaymentMethod (Id searchReqId) customerExtraFee paymentMethodId =
  updateOneWithKV
    [ Se.Set BeamSR.customerExtraFee $ customerExtraFee <&> (.amountInt),
      Se.Set BeamSR.customerExtraFeeAmount $ customerExtraFee <&> (.amount),
      Se.Set BeamSR.currency $ customerExtraFee <&> (.currency),
      Se.Set BeamSR.selectedPaymentMethodId (getId <$> paymentMethodId)
    ]
    [Se.Is BeamSR.id (Se.Eq searchReqId)]

updateAutoAssign :: (MonadFlow m, EsqDBFlow m r) => Id SearchRequest -> Bool -> Bool -> m ()
updateAutoAssign (Id searchRequestId) autoAssignedEnabled autoAssignedEnabledV2 = do
  updateOneWithKV
    [ Se.Set BeamSR.autoAssignEnabled $ Just autoAssignedEnabled,
      Se.Set BeamSR.autoAssignEnabledV2 $ Just autoAssignedEnabledV2
    ]
    [Se.Is BeamSR.id (Se.Eq searchRequestId)]

updatePaymentMethods :: (MonadFlow m, EsqDBFlow m r) => Id SearchRequest -> [Id MerchantPaymentMethod] -> m ()
updatePaymentMethods (Id searchReqId) availablePaymentMethods =
  updateOneWithKV
    [ Se.Set BeamSR.availablePaymentMethods (getId <$> availablePaymentMethods)
    ]
    [Se.Is BeamSR.id (Se.Eq searchReqId)]

instance FromTType' BeamSR.SearchRequest SearchRequest where
  fromTType' BeamSR.SearchRequestT {..} = do
    clientBundleVersion' <- mapM readVersion (strip <$> clientBundleVersion)
    clientSdkVersion' <- mapM readVersion (strip <$> clientSdkVersion)
    clientConfigVersion' <- mapM readVersion (strip <$> clientConfigVersion)
    backendConfigVersion' <- mapM readVersion (strip <$> backendConfigVersion)

    fromLocationMapping <- QLM.getLatestStartByEntityId id >>= fromMaybeM (FromLocationMappingNotFound id)
    fromLocation <- QL.findById fromLocationMapping.locationId >>= fromMaybeM (FromLocationNotFound fromLocationMapping.locationId.getId)

    mbToLocationMapping <- QLM.getLatestEndByEntityId id
    toLocation <- maybe (pure Nothing) (QL.findById . (.locationId)) mbToLocationMapping

    merchantOperatingCityId' <- backfillMOCId merchantOperatingCityId
    pure $
      Just
        SearchRequest
          { id = Id id,
            riderId = Id riderId,
            clientId = Id <$> clientId,
            distance = mkDistanceWithDefault distanceUnit distanceValue . HighPrecMeters <$> distance,
            maxDistance = mkDistanceWithDefault distanceUnit maxDistanceValue . HighPrecMeters <$> maxDistance,
            merchantId = Id merchantId,
            merchantOperatingCityId = merchantOperatingCityId',
            clientDevice = mkClientDevice clientOsType clientOsVersion,
            clientBundleVersion = clientBundleVersion',
            clientSdkVersion = clientSdkVersion',
            clientConfigVersion = clientConfigVersion',
            backendConfigVersion = backendConfigVersion',
            backendAppVersion = backendAppVersion,
            availablePaymentMethods = Id <$> availablePaymentMethods,
            selectedPaymentMethodId = Id <$> selectedPaymentMethodId,
            riderPreferredOption = fromMaybe OneWay riderPreferredOption,
            customerExtraFee = mkPriceWithDefault customerExtraFeeAmount currency <$> customerExtraFee,
            ..
          }
    where
      backfillMOCId = \case
        Just mocId -> pure $ Id mocId
        Nothing -> (.id) <$> CQM.getDefaultMerchantOperatingCity (Id merchantId)

instance ToTType' BeamSR.SearchRequest SearchRequest where
  toTType' SearchRequest {..} = do
    let distanceUnit = distance <&> (.unit) -- should be the same for all fields
    BeamSR.SearchRequestT
      { BeamSR.id = getId id,
        BeamSR.startTime = startTime,
        BeamSR.validTill = validTill,
        BeamSR.riderId = getId riderId,
        BeamSR.clientId = getId <$> clientId,
        BeamSR.fromLocationId = Just $ getId fromLocation.id,
        BeamSR.toLocationId = getId <$> (toLocation <&> (.id)),
        BeamSR.distance = getHighPrecMeters . distanceToHighPrecMeters <$> distance,
        BeamSR.distanceValue = distanceToHighPrecDistance distanceUnit <$> distance,
        BeamSR.distanceUnit,
        BeamSR.maxDistance = getHighPrecMeters . distanceToHighPrecMeters <$> maxDistance,
        BeamSR.maxDistanceValue = distanceToHighPrecDistance distanceUnit <$> maxDistance,
        BeamSR.estimatedRideDuration = estimatedRideDuration,
        BeamSR.device = device,
        BeamSR.merchantId = getId merchantId,
        BeamSR.merchantOperatingCityId = Just $ getId merchantOperatingCityId,
        BeamSR.clientOsType = clientDevice <&> (.deviceType),
        BeamSR.clientOsVersion = clientDevice <&> (.deviceVersion),
        BeamSR.clientBundleVersion = versionToText <$> clientBundleVersion,
        BeamSR.clientSdkVersion = versionToText <$> clientSdkVersion,
        BeamSR.clientConfigVersion = versionToText <$> clientConfigVersion,
        BeamSR.backendConfigVersion = versionToText <$> backendConfigVersion,
        BeamSR.backendAppVersion = backendAppVersion,
        BeamSR.language = language,
        BeamSR.disabilityTag = disabilityTag,
        BeamSR.customerExtraFee = customerExtraFee <&> (.amountInt),
        BeamSR.customerExtraFeeAmount = customerExtraFee <&> (.amount),
        BeamSR.currency = customerExtraFee <&> (.currency),
        BeamSR.autoAssignEnabled = autoAssignEnabled,
        BeamSR.autoAssignEnabledV2 = autoAssignEnabledV2,
        BeamSR.availablePaymentMethods = getId <$> availablePaymentMethods,
        BeamSR.selectedPaymentMethodId = getId <$> selectedPaymentMethodId,
        BeamSR.riderPreferredOption = Just riderPreferredOption,
        BeamSR.createdAt = createdAt
      }
