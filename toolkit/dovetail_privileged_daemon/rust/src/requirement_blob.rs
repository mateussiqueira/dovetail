const MAGIC: u32 = 0xfade_0c00;
const EXPRESSION_FORM: u32 = 1;
const MAX_DEPTH: usize = 64;

#[derive(Debug, PartialEq)]
pub(crate) enum Clause {
    And(Box<Clause>, Box<Clause>),
    Or(Box<Clause>, Box<Clause>),
    Not(Box<Clause>),
    True,
    GenericAnchor,
    Identifier(Vec<u8>),
    CdHash(Vec<u8>),
    LeafField {
        field: Vec<u8>,
        compared: Comparison,
    },
    LeafExtension {
        oid: Vec<u8>,
        compared: Comparison,
    },
    IntermediateExtension {
        oid: Vec<u8>,
        compared: Comparison,
    },
    Other,
}

#[derive(Debug, PartialEq)]
pub(crate) enum Comparison {
    Exists,
    Equals(Vec<u8>),
    Other,
}

pub(crate) fn parse(blob: &[u8]) -> anyhow::Result<Clause> {
    let mut reader = Reader { blob, at: 0 };
    anyhow::ensure!(reader.word()? == MAGIC, "o blob nao e um requisito");
    anyhow::ensure!(
        reader.word()? as usize == blob.len(),
        "tamanho do blob divergente"
    );
    anyhow::ensure!(
        reader.word()? == EXPRESSION_FORM,
        "forma de requisito desconhecida"
    );
    let clause = reader.clause(0)?;
    anyhow::ensure!(
        reader.at == blob.len(),
        "bytes sobrando depois da expressao"
    );
    Ok(clause)
}

struct Reader<'a> {
    blob: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> anyhow::Result<&'a [u8]> {
        let end = self
            .at
            .checked_add(count)
            .filter(|end| *end <= self.blob.len())
            .ok_or_else(|| anyhow::anyhow!("requisito compilado truncado"))?;
        let bytes = &self.blob[self.at..end];
        self.at = end;
        Ok(bytes)
    }

    fn word(&mut self) -> anyhow::Result<u32> {
        let bytes = self.take(4)?;
        Ok(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn data(&mut self) -> anyhow::Result<Vec<u8>> {
        let length = self.word()? as usize;
        let bytes = self.take(length)?.to_vec();
        self.take((4 - length % 4) % 4)?;
        Ok(bytes)
    }

    fn comparison(&mut self) -> anyhow::Result<Comparison> {
        match self.word()? {
            0 => Ok(Comparison::Exists),
            1 => self.data().map(Comparison::Equals),
            14 => Ok(Comparison::Other),
            2..=8 => self.data().map(|_| Comparison::Other),
            9..=13 => self.take(8).map(|_| Comparison::Other),
            other => anyhow::bail!("comparacao {other:#x} desconhecida no requisito"),
        }
    }

    fn boxed(&mut self, depth: usize) -> anyhow::Result<Box<Clause>> {
        self.clause(depth + 1).map(Box::new)
    }

    fn clause(&mut self, depth: usize) -> anyhow::Result<Clause> {
        anyhow::ensure!(depth < MAX_DEPTH, "requisito aninhado demais");
        let clause = match self.word()? {
            1 => Clause::True,
            2 => Clause::Identifier(self.data()?),
            6 => Clause::And(self.boxed(depth)?, self.boxed(depth)?),
            7 => Clause::Or(self.boxed(depth)?, self.boxed(depth)?),
            8 => Clause::CdHash(self.data()?),
            9 => Clause::Not(self.boxed(depth)?),
            op @ (11 | 14 | 17 | 22) => {
                let slot = self.word()?;
                let field = self.data()?;
                let compared = self.comparison()?;
                match (op, slot) {
                    (11, 0) => Clause::LeafField { field, compared },
                    (14, 0) => Clause::LeafExtension {
                        oid: field,
                        compared,
                    },
                    (14, 1) => Clause::IntermediateExtension {
                        oid: field,
                        compared,
                    },
                    _ => Clause::Other,
                }
            }
            15 => Clause::GenericAnchor,
            0 | 3 | 13 | 21 | 23 => Clause::Other,
            12 | 20 => self.word().map(|_| Clause::Other)?,
            18 | 19 => self.data().map(|_| Clause::Other)?,
            4 => {
                self.word()?;
                self.data().map(|_| Clause::Other)?
            }
            5 => {
                self.data()?;
                self.data().map(|_| Clause::Other)?
            }
            10 | 16 => {
                self.data()?;
                self.comparison().map(|_| Clause::Other)?
            }
            other => anyhow::bail!("opcode {other:#x} desconhecido no requisito"),
        };
        Ok(clause)
    }
}
