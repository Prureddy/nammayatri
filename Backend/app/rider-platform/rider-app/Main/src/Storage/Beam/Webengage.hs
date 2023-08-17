{-
  Copyright 2022-23, Juspay India Pvt Ltd

  This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

  as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

  is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

  the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-missing-signatures #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Storage.Beam.Webengage where

import Data.Serialize
import qualified Database.Beam as B
import Database.Beam.MySQL ()
import EulerHS.KVConnector.Types (KVConnector (..), MeshMeta (..), primaryKey, secondaryKeys, tableName)
import GHC.Generics (Generic)
import Kernel.Prelude hiding (Generic)
import Lib.UtilsTH
import Sequelize

data WebengageT f = WebengageT
  { id :: B.C f Text,
    version :: B.C f Text,
    contentTemplateId :: B.C f Text,
    principalEntityId :: B.C f Text,
    infoMessageId :: B.C f Text,
    webMessageId :: B.C f Text,
    toNumber :: B.C f Text,
    status :: B.C f (Maybe Text)
  }
  deriving (Generic, B.Beamable)

instance B.Table WebengageT where
  data PrimaryKey WebengageT f
    = Id (B.C f Text)
    deriving (Generic, B.Beamable)
  primaryKey = Id . id

type Webengage = WebengageT Identity

webengageTMod :: WebengageT (B.FieldModification (B.TableField WebengageT))
webengageTMod =
  B.tableModification
    { id = B.fieldNamed "id",
      version = B.fieldNamed "version",
      contentTemplateId = B.fieldNamed "content_template_id",
      principalEntityId = B.fieldNamed "principal_entity_id",
      infoMessageId = B.fieldNamed "info_message_id",
      webMessageId = B.fieldNamed "web_message_id",
      toNumber = B.fieldNamed "to_number",
      status = B.fieldNamed "status"
    }

$(enableKVPG ''WebengageT ['id] [['infoMessageId]])

$(mkTableInstances ''WebengageT "webengage" "atlas_app")