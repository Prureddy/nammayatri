{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Storage.Queries.PersonExtra where

import Control.Applicative ((<|>))
import Data.Text (strip)
import qualified Data.Time as T
import qualified Database.Beam as B
import Domain.Action.UI.Person
import qualified Domain.Types.Booking as Booking
import Domain.Types.Merchant (Merchant)
import qualified Domain.Types.MerchantConfig as DMC
import qualified Domain.Types.MerchantOperatingCity as DMOC
import Domain.Types.Person
import qualified EulerHS.Language as L
import Kernel.Beam.Functions
import Kernel.External.Encryption
import Kernel.External.Maps (Language)
import qualified Kernel.External.Whatsapp.Interface.Types as Whatsapp (OptApiMethods)
import Kernel.Prelude
import qualified Kernel.Types.Beckn.Context as Context
import Kernel.Types.Common
import Kernel.Types.Error
import Kernel.Types.Id
import Kernel.Types.Version
import Kernel.Utils.Common
import Kernel.Utils.Common (CacheFlow, EsqDBFlow, MonadFlow, fromMaybeM, getCurrentTime)
import Kernel.Utils.Version
import qualified Sequelize as Se
import qualified Storage.Beam.Common as BeamCommon
import qualified Storage.Beam.Person as BeamP
import qualified Storage.CachedQueries.Merchant as CQM
import Storage.Queries.OrphanInstances.Person
import Tools.Error

-- Extra code goes here --

findByPId :: (EsqDBFlow m r, MonadFlow m, CacheFlow m r) => (Kernel.Types.Id.Id Domain.Types.Person.Person -> m (Maybe Domain.Types.Person.Person))
findByPId (Kernel.Types.Id.Id id) = do findOneWithKV [Se.Is BeamP.id $ Se.Eq id]

findByEmail :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r, EncFlow m r) => Text -> m (Maybe Person)
findByEmail email_ = do
  emailDbHash <- getDbHash email_
  findOneWithKV [Se.Is BeamP.emailHash $ Se.Eq (Just emailDbHash)]

findByMobileNumberAndMerchantId :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Text -> DbHash -> Id Merchant -> m (Maybe Person)
findByMobileNumberAndMerchantId countryCode mobileNumberHash (Id merchantId) = findOneWithKV [Se.And [Se.Is BeamP.mobileCountryCode $ Se.Eq (Just countryCode), Se.Is BeamP.mobileNumberHash $ Se.Eq (Just mobileNumberHash), Se.Is BeamP.merchantId $ Se.Eq merchantId]]

findByRoleAndMobileNumberAndMerchantId :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Role -> Text -> DbHash -> Id Merchant -> m (Maybe Person)
findByRoleAndMobileNumberAndMerchantId role_ countryCode mobileNumberHash (Id merchantId) = findOneWithKV [Se.And [Se.Is BeamP.role $ Se.Eq role_, Se.Is BeamP.mobileCountryCode $ Se.Eq (Just countryCode), Se.Is BeamP.mobileNumberHash $ Se.Eq (Just mobileNumberHash), Se.Is BeamP.merchantId $ Se.Eq merchantId]]

updatePersonVersions :: (MonadFlow m, EsqDBFlow m r) => Person -> Maybe Version -> Maybe Version -> Maybe Version -> Maybe Device -> Text -> m ()
updatePersonVersions person mbClientVersion mbBundleVersion mbClientConfigVersion mbDevice deploymentVersion =
  when
    ((isJust mbBundleVersion || isJust mbClientVersion || isJust mbDevice || isJust mbClientConfigVersion) && (person.clientBundleVersion /= mbBundleVersion || person.clientSdkVersion /= mbClientVersion || person.clientConfigVersion /= mbClientConfigVersion || person.clientDevice /= mbDevice || person.backendAppVersion /= Just deploymentVersion))
    do
      now <- getCurrentTime
      updateWithKV
        [ Se.Set BeamP.updatedAt now,
          Se.Set BeamP.clientSdkVersion (versionToText <$> (mbClientVersion <|> person.clientSdkVersion)),
          Se.Set BeamP.clientBundleVersion (versionToText <$> (mbBundleVersion <|> person.clientBundleVersion)),
          Se.Set BeamP.clientConfigVersion (versionToText <$> mbClientConfigVersion),
          Se.Set BeamP.clientOsType ((.deviceType) <$> mbDevice),
          Se.Set BeamP.clientOsVersion ((.deviceVersion) <$> mbDevice),
          Se.Set BeamP.backendAppVersion (Just deploymentVersion)
        ]
        [Se.Is BeamP.id (Se.Eq (getId (person.id)))]

updatePersonalInfo ::
  (MonadFlow m, EsqDBFlow m r) =>
  Id Person ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe (EncryptedHashed Text) ->
  Maybe Text ->
  Maybe Text ->
  Maybe Language ->
  Maybe Gender ->
  Maybe Version ->
  Maybe Version ->
  Maybe Version ->
  Maybe Device ->
  Text ->
  m ()
updatePersonalInfo (Id personId) mbFirstName mbMiddleName mbLastName mbReferralCode mbEncEmail mbDeviceToken mbNotificationToken mbLanguage mbGender mbClientVersion mbBundleVersion mbClientConfigVersion mbDevice deploymentVersion = do
  now <- getCurrentTime
  let mbEmailEncrypted = mbEncEmail <&> unEncrypted . (.encrypted)
  let mbEmailHash = mbEncEmail <&> (.hash)
  updateWithKV
    ( [Se.Set BeamP.updatedAt now]
        <> [Se.Set BeamP.firstName mbFirstName | isJust mbFirstName]
        <> [Se.Set BeamP.middleName mbMiddleName | isJust mbMiddleName]
        <> [Se.Set BeamP.lastName mbLastName | isJust mbLastName]
        <> [Se.Set BeamP.emailEncrypted mbEmailEncrypted | isJust mbEmailEncrypted]
        <> [Se.Set BeamP.emailHash mbEmailHash | isJust mbEmailHash]
        <> [Se.Set BeamP.deviceToken mbDeviceToken | isJust mbDeviceToken]
        <> [Se.Set BeamP.notificationToken mbNotificationToken | isJust mbNotificationToken]
        <> [Se.Set BeamP.referralCode mbReferralCode | isJust mbReferralCode]
        <> [Se.Set BeamP.referredAt (Just now) | isJust mbReferralCode]
        <> [Se.Set BeamP.language mbLanguage | isJust mbLanguage]
        <> [Se.Set BeamP.gender (fromJust mbGender) | isJust mbGender]
        <> [Se.Set BeamP.clientSdkVersion (versionToText <$> mbClientVersion) | isJust mbClientVersion]
        <> [Se.Set BeamP.clientBundleVersion (versionToText <$> mbBundleVersion) | isJust mbBundleVersion]
        <> [Se.Set BeamP.clientConfigVersion (versionToText <$> mbClientConfigVersion) | isJust mbClientConfigVersion]
        <> [Se.Set BeamP.clientOsType ((.deviceType) <$> mbDevice) | isJust mbDevice]
        <> [Se.Set BeamP.clientOsVersion ((.deviceVersion) <$> mbDevice) | isJust mbDevice]
        <> [Se.Set BeamP.backendAppVersion (Just deploymentVersion)]
    )
    [Se.Is BeamP.id (Se.Eq personId)]

findBlockedByDeviceToken :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r, EncFlow m r) => Maybe Text -> m [Person]
findBlockedByDeviceToken Nothing = return [] -- return empty array in case device token is Nothing (WARNING: DON'T REMOVE IT)
findBlockedByDeviceToken deviceToken = findAllWithKV [Se.And [Se.Is BeamP.deviceToken (Se.Eq deviceToken), Se.Is BeamP.blocked (Se.Eq True)]]

updatingEnabledAndBlockedState :: (MonadFlow m, EsqDBFlow m r) => Id Person -> Maybe (Id DMC.MerchantConfig) -> Bool -> m ()
updatingEnabledAndBlockedState (Id personId) blockedByRule isBlocked = do
  now <- getCurrentTime
  updateWithKV
    ( [ Se.Set BeamP.enabled (not isBlocked),
        Se.Set BeamP.blocked isBlocked,
        Se.Set BeamP.blockedByRuleId $ getId <$> blockedByRule,
        Se.Set BeamP.updatedAt now
      ]
        <> [Se.Set BeamP.blockedAt (Just $ T.utcToLocalTime T.utc now) | isBlocked]
    )
    [Se.Is BeamP.id (Se.Eq personId)]

findAllCustomers :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Merchant -> DMOC.MerchantOperatingCity -> Int -> Int -> Maybe Bool -> Maybe Bool -> Maybe DbHash -> m [Person]
findAllCustomers merchant moCity limitVal offsetVal mbEnabled mbBlocked mbSearchPhoneDBHash =
  findAllWithOptionsDb
    [ Se.And
        ( [ Se.Is BeamP.merchantId (Se.Eq (getId merchant.id)),
            Se.Is BeamP.role (Se.Eq USER)
          ]
            <> [Se.Is BeamP.enabled $ Se.Eq (fromJust mbEnabled) | isJust mbEnabled]
            <> [Se.Is BeamP.blocked $ Se.Eq (fromJust mbBlocked) | isJust mbBlocked]
            <> ([Se.Is BeamP.mobileNumberHash $ Se.Eq mbSearchPhoneDBHash | isJust mbSearchPhoneDBHash])
            <> [ Se.Or
                   ( [Se.Is BeamP.merchantOperatingCityId $ Se.Eq $ Just (getId moCity.id)]
                       <> [Se.Is BeamP.merchantOperatingCityId $ Se.Eq Nothing | moCity.city == merchant.defaultCity]
                   )
               ]
        )
    ]
    (Se.Asc BeamP.firstName)
    (Just limitVal)
    (Just offsetVal)

fetchRidesCount :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> m (Maybe Int)
fetchRidesCount personId = do
  dbConf <- getMasterBeamConfig
  res <- L.runDB dbConf $
    L.findRows $
      B.select $
        B.aggregate_ (\_ -> B.as_ @Int B.countAll_) $
          B.filter_'
            ( \booking ->
                B.sqlBool_ (booking.status `B.in_` (B.val_ <$> [Booking.COMPLETED, Booking.TRIP_ASSIGNED]))
                  B.&&?. booking.riderId B.==?. B.val_ (getId personId)
            )
            do
              B.all_ (BeamCommon.booking BeamCommon.atlasDB)
  pure $ either (const Nothing) (\r -> if null r then Nothing else Just (head r)) res

findCityInfoById :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> m (Maybe PersonCityInformation)
findCityInfoById personId = do
  person <- findByPId personId
  case person of
    Nothing -> pure Nothing
    Just Person {..} -> pure $ Just $ PersonCityInformation {personId = id, ..}

updateEmergencyInfo ::
  (MonadFlow m, EsqDBFlow m r) =>
  Id Person ->
  Maybe Bool ->
  Maybe RideShareOptions ->
  Maybe Bool ->
  Maybe Bool ->
  m ()
updateEmergencyInfo (Id personId) shareEmergencyContacts shareTripWithEmergencyContactOption nightSafetyChecks hasCompletedSafetySetup = do
  now <- getCurrentTime
  updateWithKV
    ( [Se.Set BeamP.updatedAt now]
        <> [Se.Set BeamP.shareEmergencyContacts (fromJust shareEmergencyContacts) | isJust shareEmergencyContacts]
        <> [Se.Set BeamP.shareTripWithEmergencyContactOption shareTripWithEmergencyContactOption | isJust shareTripWithEmergencyContactOption]
        <> [Se.Set BeamP.nightSafetyChecks (fromJust nightSafetyChecks) | isJust nightSafetyChecks]
        <> [Se.Set BeamP.hasCompletedSafetySetup (fromJust hasCompletedSafetySetup) | isJust hasCompletedSafetySetup]
    )
    [Se.Is BeamP.id (Se.Eq personId)]

updateSafetyCenterBlockingCounter :: (MonadFlow m, EsqDBFlow m r) => Id Person -> Maybe Int -> Maybe UTCTime -> m ()
updateSafetyCenterBlockingCounter personId counter mbDate = do
  now <- getCurrentTime
  updateWithKV
    ( [ Se.Set BeamP.updatedAt now,
        Se.Set BeamP.safetyCenterDisabledOnDate mbDate
      ]
        <> [Se.Set BeamP.falseSafetyAlarmCount counter | isJust counter]
    )
    [ Se.Is BeamP.id $ Se.Eq $ getId personId
    ]

updateCityInfoById :: (MonadFlow m, EsqDBFlow m r) => Id Person -> Context.City -> Id DMOC.MerchantOperatingCity -> m ()
updateCityInfoById (Id personId) currentCity (Id merchantOperatingCityId) = do
  now <- getCurrentTime
  updateOneWithKV
    [ Se.Set BeamP.currentCity (Just currentCity),
      Se.Set BeamP.merchantOperatingCityId (Just merchantOperatingCityId),
      Se.Set BeamP.updatedAt now
    ]
    [Se.Is BeamP.id (Se.Eq personId)]

updateHasTakenValidRide :: (MonadFlow m, EsqDBFlow m r) => Id Person -> m ()
updateHasTakenValidRide (Id personId) = do
  now <- getCurrentTime
  updateWithKV
    [ Se.Set BeamP.hasTakenValidRide True,
      Se.Set BeamP.updatedAt now
    ]
    [Se.Is BeamP.id (Se.Eq personId)]

updateReferredByCustomer :: (MonadFlow m, EsqDBFlow m r) => Id Person -> Text -> m () -- TODO: move this once DSL Bug Fixed
updateReferredByCustomer personId referredByPersonId = do
  now <- getCurrentTime
  updateWithKV
    [ Se.Set BeamP.referredByCustomer (Just referredByPersonId),
      Se.Set BeamP.updatedAt now
    ]
    [ Se.Is BeamP.id $ Se.Eq $ getId personId
    ]

updateCustomerReferralCode :: (MonadFlow m, EsqDBFlow m r) => Id Person -> Text -> m () -- TODO: move this once DSL Bug Fixed
updateCustomerReferralCode personId refferalCode = do
  now <- getCurrentTime
  updateWithKV
    [ Se.Set BeamP.customerReferralCode (Just refferalCode),
      Se.Set BeamP.updatedAt now
    ]
    [ Se.Is BeamP.id $ Se.Eq $ getId personId
    ]
