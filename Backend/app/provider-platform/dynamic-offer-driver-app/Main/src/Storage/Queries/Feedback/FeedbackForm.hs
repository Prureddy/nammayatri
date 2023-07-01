{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Storage.Queries.Feedback.FeedbackForm where

import Domain.Types.Feedback.FeedbackForm
import Kernel.Prelude
import Kernel.Storage.Esqueleto as Esq
import Storage.Tabular.Feedback.FeedbackForm

findAllFeedback :: Transactionable m => m [FeedbackFormRes]
findAllFeedback = Esq.findAll $ do
  from $ table @FeedbackFormT

findAllFeedbackByRating :: Transactionable m => Int -> m [FeedbackFormRes]
findAllFeedbackByRating rating =
  Esq.findAll $ do
    feedbackForm <- from $ table @FeedbackFormT
    where_ $
      feedbackForm ^. FeedbackFormRating ==. val (Just rating)
        ||. Esq.isNothing (feedbackForm ^. FeedbackFormRating)
    pure feedbackForm
