{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Storage.Clickhouse.Booking where

import qualified Domain.Types.Booking as DB
import qualified Domain.Types.Location as DL
import qualified Domain.Types.Merchant as DM
import qualified Domain.Types.Person as DP
import Kernel.Prelude
import Kernel.Storage.ClickhouseV2 as CH
import qualified Kernel.Storage.ClickhouseV2.UtilsTH as TH
import Kernel.Types.Id

data BookingT f = BookingT
  { id :: C f (Id DB.Booking),
    riderId :: C f (Id DP.Person),
    status :: C f DB.BookingStatus,
    fromLocationId :: C f (Maybe (Id DL.Location)),
    toLocationId :: C f (Maybe (Id DL.Location)),
    merchantId :: C f (Id DM.Merchant),
    createdAt :: C f UTCTime
  }
  deriving (Generic)

deriving instance Show Booking

-- TODO move to TH (quietSnake)
bookingTTable :: BookingT (FieldModification BookingT)
bookingTTable =
  BookingT
    { id = "id",
      riderId = "rider_id",
      status = "status",
      fromLocationId = "from_location_id",
      toLocationId = "to_location_id",
      merchantId = "merchant_id",
      createdAt = "created_at"
    }

type Booking = BookingT Identity

$(TH.mkClickhouseInstances ''BookingT)

findAllCompletedRiderBookingsByMerchantInRange ::
  CH.HasClickhouseEnv CH.APP_SERVICE_CLICKHOUSE m =>
  Id DM.Merchant ->
  Id DP.Person ->
  UTCTime ->
  UTCTime ->
  m [Booking]
findAllCompletedRiderBookingsByMerchantInRange merchantId riderId from to =
  CH.findAll $
    CH.select $
      CH.filter_
        ( \booking _ ->
            booking.merchantId CH.==. merchantId
              CH.&&. booking.riderId CH.==. riderId
              CH.&&. booking.status CH.==. DB.COMPLETED
              CH.&&. booking.createdAt >=. from
              CH.&&. booking.createdAt <=. to
        )
        (CH.all_ @CH.APP_SERVICE_CLICKHOUSE bookingTTable)
