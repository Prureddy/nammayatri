{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module API.UI.Booking
  ( DBooking.BookingListRes,
    API,
    handler,
    bookingStatus,
    bookingList,
  )
where

import qualified Domain.Action.UI.Booking as DBooking
import qualified Domain.Types.Booking as SRB
import Domain.Types.Booking.API (BookingAPIEntity)
import qualified Domain.Types.Client as DC
import qualified Domain.Types.Merchant as Merchant
import qualified Domain.Types.Person as Person
import Environment
import EulerHS.Prelude hiding (id)
import Kernel.Types.APISuccess
import Kernel.Types.Id
import Kernel.Utils.Common
import Servant
import Storage.Beam.SystemConfigs ()
import Tools.Auth

type API =
  "rideBooking"
    :> ( Capture "rideBookingId" (Id SRB.Booking)
           :> TokenAuth
           :> Post '[JSON] BookingAPIEntity
           :<|> "list"
             :> TokenAuth
             :> QueryParam "limit" Integer
             :> QueryParam "offset" Integer
             :> QueryParam "onlyActive" Bool
             :> QueryParam "status" SRB.BookingStatus
             :> QueryParam "clientId" (Id DC.Client)
             :> Get '[JSON] DBooking.BookingListRes
           :<|> Capture "rideBookingId" (Id SRB.Booking)
             :> TokenAuth
             :> "addStop"
             :> ReqBody '[JSON] DBooking.StopReq
             :> Post '[JSON] APISuccess
           :<|> Capture "rideBookingId" (Id SRB.Booking)
             :> TokenAuth
             :> "editStop"
             :> ReqBody '[JSON] DBooking.StopReq
             :> Post '[JSON] APISuccess
       )

handler :: FlowServer API
handler =
  bookingStatus
    :<|> bookingList
    :<|> addStop
    :<|> editStop

bookingStatus :: Id SRB.Booking -> (Id Person.Person, Id Merchant.Merchant) -> FlowHandler BookingAPIEntity
bookingStatus bookingId = withFlowHandlerAPI . DBooking.bookingStatus bookingId

addStop :: Id SRB.Booking -> (Id Person.Person, Id Merchant.Merchant) -> DBooking.StopReq -> FlowHandler APISuccess
addStop bookingId (personId, merchantId) addStopReq = withFlowHandlerAPI . withPersonIdLogTag personId $ DBooking.addStop (personId, merchantId) bookingId addStopReq

editStop :: Id SRB.Booking -> (Id Person.Person, Id Merchant.Merchant) -> DBooking.StopReq -> FlowHandler APISuccess
editStop bookingId (personId, merchantId) editStopReq = withFlowHandlerAPI . withPersonIdLogTag personId $ DBooking.editStop (personId, merchantId) bookingId editStopReq

bookingList :: (Id Person.Person, Id Merchant.Merchant) -> Maybe Integer -> Maybe Integer -> Maybe Bool -> Maybe SRB.BookingStatus -> Maybe (Id DC.Client) -> FlowHandler DBooking.BookingListRes
bookingList (personId, merchantId) mbLimit mbOffset mbOnlyActive mbClientId = withFlowHandlerAPI . DBooking.bookingList (personId, merchantId) mbLimit mbOffset mbOnlyActive mbClientId
