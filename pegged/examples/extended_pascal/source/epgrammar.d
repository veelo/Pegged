﻿module epgrammar;

// Extended Pascal grammar.
// Comments refer to the section numbers in the standard:
// http://dx.doi.org/10.1109/IEEESTD.1990.101061
// http://pascal-central.com/docs/iso10206.pdf
//
// Uses extended PEG syntax:
// https://github.com/PhilippeSigaud/Pegged/wiki/Extended-PEG-Syntax
//
// Minor edits have been made, marked with BNV, with the following objectives:
// 1 - Retain layout and comments.
// 2 - Reorder choices from long to short in order to get the longest match.
// 3 - Identify certain identifiers in the translator.
//
// In addition, the following Prospero extensions have been added, marked with Prospero
// 1 - Type viewing (casting) with the '::' operator.
// 2 - Labels can be identifiers

enum EPgrammar = `
EP:
    BNVCompileUnit  <- Program eoi

# 6.1.1
    Digit           <- digit
    Letter          <- [a-zA-Z]

# 6.1.3
    BNVAnyIdentifier    <~ Letter ( "_"? ( Letter / Digit ) )*
    Identifier          <- BNVAnyIdentifier {failOnWordSymbol}

# 6.1.4 (complete)
    RemoteDirective <- "forward"i / "external"i

# 6.1.5 (complete)
    InterfaceDirective <- "interface"i / "external"i

# 6.1.6 (complete)
    ImplementationDirective <- "implementation"i

# 6.1.7 (complete)
    SignedNumber    <- SignedReal / SignedInteger       # BNV changed order: real match is always longer dan integer match.
    SignedReal      <~ Sign? UnsignedReal
    SignedInteger   <~ Sign? UnsignedInteger
    UnsignedNumber  <- UnsignedReal / UnsignedInteger   # BNV changed order: real match is always longer dan integer match.
    Sign            <- [-+]
    UnsignedReal    <~ DigitSequence "." FractionalPart ( [eE] ScaleFactor )? | DigitSequence [eE] ScaleFactor
    UnsignedInteger <- DigitSequence
    FractionalPart  <- DigitSequence
    ScaleFactor     <~ Sign? DigitSequence
    DigitSequence   <~ digits
    Number          <~ SignedNumber | Sign? ( DigitSequence "." / "." FractionalPart ) ( [eE] ScaleFactor )?
    ExtendedDigit   <- Digit / Letter
    ExtendedNumber  <- UnsignedInteger "#" ExtendedDigit+

# 6.1.8 (complete)
#    Label   <- DigitSequence
# Prospero supports identifiers as labels:
    Label   <- DigitSequence / Identifier

# 6.1.9 (complete)
    CharacterString <- "'" StringElement* "'"
    StringElement   <- ApostropheImage / StringCharacter
    ApostropheImage <- "''"
    StringCharacter <- !"'" .

# 6.1.10 Token separators
    Spacing         <~ blank+   # BNV Do not discard spacing.
    _               <- ( Spacing / TrailingComment / InlineComment )*
    Comment         <- ( :Spacing / TrailingComment / InlineComment )+
    CommentOpen     <-  "{" / "(*"
    CommentClose    <-  "}" / "*)"
    CommentContent  <~ ( !CommentClose . )*
    InlineComment   <- CommentOpen CommentContent CommentClose !endOfLine
    TrailingComment <- CommentOpen CommentContent CommentClose &endOfLine

# 6.2.1 (complete)
    Block                               <- ImportPart ( _ ( LabelDeclarationPart / ConstantDefinitionPart / TypeDefinitionPart / VariableDeclarationPart / ProcedureAndFunctionDeclarationPart ) )* _ StatementPart _
    ImportPart                          <- (:IMPORT _ ( ImportSpecification _ :";" _ )+ )?
    LabelDeclarationPart                <- :LABEL _ Label ( _ "," _ Label )* _ :";" _
    ConstantDefinitionPart              <- :CONST _ ( ConstantDefinition _ :";" _ )+
    TypeDefinitionPart                  <- :TYPE _ ( ( TypeDefinition / SchemaDefinition) _ :";" _ )+
    VariableDeclarationPart             <- :VAR _ ( VariableDeclaration _ :";" _ )+
    ProcedureAndFunctionDeclarationPart <- ( ( ProcedureDeclaration / FunctionDeclaration ) _ :";" _ )*
    StatementPart                       <- CompoundStatement

# 6.3.1 (complete)
    ConstantDefinition  <- Identifier _ "=" _ ConstantExpression
    ConstantIdentifier  <- Identifier
    ConstantName        <- ( ImportedInterfaceIdentifier _ DOT _ )? ConstantIdentifier

# 6.4.1 (complete)
    TypeDefinition      <- BNVTypeDefName _ "=" _ TypeDenoter
    TypeDenoter         <- :(BINDABLE _ )? ( TypeName | NewType | TypeInquiry | DiscriminatedSchema ) _ InitialStateSpecifier?
    NewType             <- NewOrdinalType | NewStructuredType | NewPointerType | RestrictedType
    #SimpleTypeName      <- TypeName    # BNV Semantic only
    StructuredTypeName  <- ArrayTypeName / RecordTypeName / SetTypeName / FileTypeName
    ArrayTypeName       <- TypeName
    RecordTypeName      <- TypeName
    SetTypeName         <- TypeName
    FileTypeName        <- TypeName
    #PointerTypeName     <- TypeName    # BNV Semantic only
    TypeIdentifier      <- Identifier
    TypeName            <- ( ImportedInterfaceIdentifier _ DOT _ )? TypeIdentifier
#BNV extensions
    BNVTypeDefName      <- Identifier

# 6.4.2.1 (complete)
    #SimpleType          <- OrdinalType / RealTypeName / ComplexTypeName    # BNV Semantic only
    OrdinalType         <- NewOrdinalType | OrdinalTypeName | TypeInquiry | DiscriminatedSchema
    NewOrdinalType      <- EnumeratedType | SubrangeType
    OrdinalTypeName     <- TypeName
    #RealTypeName        <- TypeName    # BNV Semantic only
    #ComplexTypeName     <- TypeName    # BNV Semantic only

# 6.4.2.3 (complete)
    EnumeratedType      <- "(" _ IdentifierList _ ")"
    IdentifierList      <- Identifier ( _ COMMA _ Identifier )*

# 6.4.2.4 (complete)
    SubrangeType        <- SubrangeBound _ ".." _ SubrangeBound
    SubrangeBound       <- Expression

# 6.4.2.5 (complete)
    RestrictedType      <- :RESTRICTED _ TypeName

# 6.4.3.1 (complete)
    #StructuredType          <- NewStructuredType / StructuredTypeName  # BNV Semantic only
    NewStructuredType       <- :PACKED? _ UnpackedStructuredType
    UnpackedStructuredType  <- ArrayType / RecordType / SetType / FileType

# 6.4.3.2 (complete)
    ArrayType           <- :ARRAY _ "[" _ IndexType ( _ COMMA _ IndexType )* _ "]" _ :OF _ ComponentType
    IndexType           <- OrdinalType
    ComponentType       <- TypeDenoter

# 6.4.3.3 String types. TODO

# 6.4.3.4 (complete)
    RecordType          <- :RECORD _ FieldList _ :END
    FieldList           <- ( ( FixedPart ( _ ";" _ VariantPart )? / VariantPart ) _ ";"? )?
    FixedPart           <- RecordSection ( _ ";" _ RecordSection )*
    RecordSection       <- IdentifierList _ ":" _ TypeDenoter
    FieldIdentifier     <- Identifier
    VariantPart         <- :CASE _ VariantSelector _ :OF _ ( VariantListElement ( _ ";" _ VariantListElement )* ( _ ":"? _ VariantPartCompleter )? | VariantPartCompleter )
    VariantListElement  <- CaseConstantList _ ":" _ VariantDenoter
    VariantPartCompleter    <- OTHERWISE _ VariantDenoter
    VariantDenoter      <- "(" _ FieldList _ ")"
    VariantSelector     <- ( TagField _ ":" _ )? TagType | DiscriminantIdentifier
    TagField            <- Identifier
    TagType             <- OrdinalTypeName
    CaseConstantList    <- CaseRange ( _ "," _ CaseRange )*
    CaseRange           <- CaseConstant ( _ ".." _ CaseConstant )?
    CaseConstant        <- ConstantExpression

# 6.4.3.5 (complete)
    SetType             <- :SET _ :OF _ BaseType
    BaseType            <- OrdinalType

# 6.4.3.6 (complete)
    FileType            <- :FILE _ ( "[" _ IndexType _ "]" _ )? :OF _ ComponentType

# 6.4.4 (complete)
    #PointerType         <- NewPointerType / PointerTypeName    # BNV Semantic only
    NewPointerType      <- :"^" _ DomainType
    DomainType          <- TypeName | SchemaName

# 6.4.7 (complete)
    SchemaDefinition            <- ( Identifier _ "=" _ SchemaName ) | ( Identifier _ FormalDiscriminantPart _ "=" _ TypeDenoter )
    FormalDiscriminantPart      <- "(" _ DiscriminantSpecification ( _ ";" _ DiscriminantSpecification )* _ ")"
    DiscriminantSpecification   <- IdentifierList _ ":" _ OrdinalTypeName
    DiscriminantIdentifier      <- Identifier
    SchemaIdentifier            <- Identifier
    SchemaName                  <- ( ImportedInterfaceIdentifier _ "." _ )? SchemaIdentifier

# 6.4.8 (complete)
    DiscriminatedSchema     <- SchemaName _ ActualDiscriminantPart
    ActualDiscriminantPart  <- "(" _ DiscriminantValue _ ( "," _ DiscriminantValue _ )* ")"
    DiscriminantValue       <- Expression

# 6.4.9 (complete)
    TypeInquiry         <- :TYPE _ :OF _ TypeInquiryObject
    TypeInquiryObject   <- VariableName / ParameterIdentifier

# 6.5.1 (complete)
    VariableDeclaration <- IdentifierList _ ":" _ TypeDenoter
    VariableIdentifier  <- Identifier
    VariableName        <- ( ImportedInterfaceIdentifier _ DOT _ )? VariableIdentifier
#    VariableAccess      <- EntireVariable | ComponentVariable | IdentifiedVariable | BufferVariable | SubstringVariable | FunctionIdentifiedVariable
# Prospero extension: type viewing.
    VariableAccess      <- ( EntireVariable | ComponentVariable | IdentifiedVariable | BufferVariable | SubstringVariable | FunctionIdentifiedVariable ) ( _ "::" _ TypeName)?

# 6.5.2 (complete)
    EntireVariable      <- VariableName

# 6.5.3.1 (complete)
    ComponentVariable   <- IndexedVariable | FieldDesignator

# 6.5.3.2 (complete)
    IndexedVariable     <- (ArrayVariable _ "[" _ IndexExpression ( _ "," _ IndexExpression )* _ "]" ) | ( StringVariable _ "[" _ IndexExpression _ "]" )
    ArrayVariable       <- VariableAccess
    StringVariable      <- VariableAccess
    IndexExpression     <- Expression

# 6.5.3.3 (complete)
    FieldDesignator     <- ( RecordVariable _ "." _ FieldSpecifier ) | FieldDesignatorIdentifier
    RecordVariable      <- VariableAccess
    FieldSpecifier      <- FieldIdentifier

# 6.5.4 (complete)
    IdentifiedVariable  <- PointerVariable _ :"^"
    PointerVariable     <- VariableAccess

# 6.5.5 (complete)
    BufferVariable      <- FileVariable _ :"^"
    FileVariable        <- VariableAccess

# 6.5.6 (complete)
    SubstringVariable   <- StringVariable _ "[" _ IndexExpression _ ".." _ IndexExpression _ "]"

# 6.6 (complete)
    InitialStateSpecifier   <- VALUE _ ComponentValue

# 6.7.1 (complete)
    ProcedureDeclaration    <- ProcedureHeading _ ";" _ RemoteDirective
                             | ProcedureIdentification _ ";" _ ProcedureBlock
                             | ProcedureHeading _ ";" _ ProcedureBlock
    ProcedureHeading        <- PROCEDURE _ Identifier ( _ FormalParameterList )?
    ProcedureIdentification <- PROCEDURE _ ProcedureIdentifier
    ProcedureIdentifier     <- Identifier
    ProcedureBlock          <- Block
    ProcedureName           <- ( ImportedInterfaceIdentifier _ DOT _ )? ProcedureIdentifier

# 6.7.2 (complete)
    FunctionDeclaration         <- FunctionHeading _ ";" _ RemoteDirective
                                 | FunctionIdentification _ ";" _ FunctionBlock
                                 | FunctionHeading _ ";" _ FunctionBlock
    FunctionHeading             <- :FUNCTION _ Identifier ( _ FormalParameterList )? ( _ ResultVariableSpecification )? _ ":" _ ResultType
    ResultVariableSpecification <- "=" _ Identifier
    FunctionIdentification      <- :FUNCTION _ FunctionIdentifier
    FunctionIdentifier          <- Identifier
    ResultType                  <- TypeName
    FunctionBlock               <- Block
    FunctionName                <- ( ImportedInterfaceIdentifier _ DOT _ )? FunctionIdentifier

# 6.7.3.1 (complete)
    FormalParameterList                 <- "(" _ FormalParameterSection ( _ ";" _ FormalParameterSection )* _ ")"
    FormalParameterSection              <- ValueParameterSpecification
                                         | VariableParameterSpecification
                                         | ProceduralParameterSpecification
                                         | FunctionalParameterSpecification
                                         | ConformantArrayParameterSpecification    # BNV moved from section 6.7.3.7.1
    ValueParameterSpecification         <- (PROTECTED _ )? IdentifierList _ ":" _ ParameterForm
    VariableParameterSpecification      <- (PROTECTED _ )? VAR _ IdentifierList _ ":" _ ParameterForm
    ParameterForm                       <- TypeName | SchemaName | TypeInquiry
    ParameterIdentifier                 <- Identifier
    ProceduralParameterSpecification    <- ProcedureHeading
    FunctionalParameterSpecification    <- FunctionHeading

# 6.7.3.7.1
#    FormalParameterSection                  <- ConformantArrayParameterSpecification   # BNV Moved to section 6.7.3.1
    ConformantArrayParameterSpecification   <- ( PROTECTED _ )? ( ValueConformantArraySpecification | VariableConformantArraySpecification )
    ValueConformantArraySpecification       <- IdentifierList _ ":" _ ConformantArrayForm
    VariableConformantArraySpecification    <- VAR _ IdentifierList _ ":" _ ConformantArrayForm
    ConformantArrayForm                     <- PackedConformantArrayForm / UnpackedConformantArrayForm
    PackedConformantArrayForm               <- PACKED _ ARRAY _ "[" _ IndexTypeSpecification _ "]" _ OF _ TypeName
    UnpackedConformantArrayForm             <- ARRAY _ "[" _ IndexTypeSpecification ( _ ";" _ IndexTypeSpecification )* _ "]" _ OF _ TypeName
    IndexTypeSpecification                  <- Identifier _ ".." _ Identifier _ ":" _ OrdinalTypeName
# TODO mistake in standard?
#    Primary                                 <- BoundIdentifier
#    BoundIdentifier                         <- Identifier

# 6.7.5 Required procedures TODO

# 6.7.5.5 (complete)
    ReadstrParameterList    <- "(" _ StringExpression _ "," _ VariableAccess ( _ "," _ VariableAccess )* _ ")"
    StringExpression        <- Expression
    WritestrParameterList   <- "(" _ StringVariable _ "," _ WriteParameter ( _ "," _ WriteParameter )* _ ")"

# 6.7.6 Required functions TODO

# 6.8.1 (complete)
    Expression          <- SimpleExpression ( _ RelationalOperator _ SimpleExpression)?
    SimpleExpression    <- Sign? _ Term ( _ AddingOperator _ Term )*
    Term                <- Factor ( _ MultiplyingOperator _ Factor )*
    Factor              <- Primary ( _ ExponentiatingOperator _ Primary )?
    Primary             <- VariableAccess
                         | UnsignedConstant
                         | SetConstructor
                         | FunctionAccess
                         | "(" _ Expression _ ")"
                         | NOT _ Primary
                         | ConstantAccess
                         | SchemaDiscriminant
                         | StructuredValueConstructor
                         | DiscriminantIdentifier
    UnsignedConstant    <- UnsignedNumber | CharacterString | NIL | ExtendedNumber
    SetConstructor      <- "[" _ ( MemberDesignator ( _ "," _ MemberDesignator )* )? _ "]"
    MemberDesignator    <- Expression ( _ ".." _ Expression )?

# 6.8.2 (complete)
    ConstantExpression  <- Expression

# 6.8.3.1 (complete)
    ExponentiatingOperator  <- "**" / POW
    MultiplyingOperator     <- "*" / "/" / DIV / MOD / AND_THEN / AND       # BNV Try to match AND_THEN before AND
    AddingOperator          <- "+" / "-" / "><" / OR_ELSE / OR              # BNV Try to match OR_ELSE before OR
    RelationalOperator      <- "=" / "<>" / "<=" / "<" / ">=" / ">" / IN

# 6.8.3.2 Arithmetic operators TODO?

# 6.8.3.3
    BooleanExpression       <- Expression

# 6.8.3.4 Set operators TODO

# 6.8.3.6 String operator TODO

# 6.8.4 (complete)
    SchemaDiscriminant      <- ( VariableAccess / ConstantAccess ) _ "." _ DiscriminantSpecifier | SchemaDiscriminantIdentifier
    DiscriminantSpecifier   <- DiscriminantIdentifier


# 6.8.5 (complete)
    FunctionDesignator      <- FunctionName ( _ ActualParameterList )?
    ActualParameterList     <- "(" _ ActualParameter ( _ "," _ ActualParameter )* _ ")"
    ActualParameter         <- Expression / VariableAccess / ProcedureName / FunctionName

# 6.8.6.1 (complete)
    #FunctionAccess          <- EntireFunctionAccess / ComponentFunctionAccess / SubstringFunctionAccess
# Prospero extension: type viewing.
    FunctionAccess          <- ( EntireFunctionAccess | ComponentFunctionAccess | SubstringFunctionAccess ) ( _ "::" _ TypeName)?
    ComponentFunctionAccess <- IndexedFunctionAccess / RecordFunctionAccess
    EntireFunctionAccess    <- FunctionDesignator

# 6.8.6.2 (complete)
    IndexedFunctionAccess   <- ArrayFunction _ "[" _ IndexExpression ( _ "," _ IndexExpression )* _ "]"
    ArrayFunction           <- FunctionAccess
    StringFunction          <- FunctionAccess

# 6.8.6.3 (complete)
    RecordFunctionAccess    <- RecordFunction _ "." _ FieldSpecifier
    RecordFunction          <- FunctionAccess

# 6.8.6.4 (complete)
    FunctionIdentifiedVariable  <- PointerFunction _ "^"
    PointerFunction             <- FunctionAccess

# 6.8.6.5 (complete)
    SubstringFunctionAccess <- StringFunction _ "[" _ IndexExpression _ ".." _ IndexExpression _ "]"

# 6.8.7.1 (complete)
    StructuredValueConstructor  <- ArrayTypeName _ ArrayValue | RecordTypeName _ RecordValue | SetTypeName _ SetValue
    ComponentValue  <- Expression | ArrayValue | RecordValue

# 6.8.7.2 (complete)
    ArrayValue          <- "[" _ ( ArrayValueElement ( _ ";" _ ArrayValueElement )* _ ";"? )? ( _ ArrayValueCompleter _ ";"? )? _ "]"
    ArrayValueElement   <- CaseConstantList _ ":" _ ComponentValue
    ArrayValueCompleter <- OTHERWISE _ ComponentValue

# 6.8.7.3 (complete)
    RecordValue         <- "[" _ FieldListValue _ "]"
    FieldListValue      <- ( ( FixedPartValue ( _ ";" _ VariantPartValue )? / VariantPartValue ) _ ";"? )?
    FixedPartValue      <- FieldValue ( _ ";" _ FieldValue )*
    FieldValue          <- FieldIdentifier ( _ ";" _ FieldIdentifier )* _ ":" _ ComponentValue
    VariantPartValue    <- CASE _ ( TagFieldIdentifier _ ":" _)? ConstantTagValue _ OF _ "[" _ FieldListValue _ "]"
    ConstantTagValue    <- ConstantExpression
    TagFieldIdentifier  <- FieldIdentifier

# 6.8.7.4 (complete)
    SetValue            <- SetConstructor

# 6.8.8.1 (complete)
    ConstantAccess          <- ConstantAccessComponent / ConstantName
    ConstantAccessComponent <- IndexedConstant | FieldDesignatedConstant | SubstringConstant

# 6.8.8.2 (complete)
    IndexedConstant <- ArrayConstant _ "[" _ IndexExpression ( _ "," _ IndexExpression )* _ "]" | StringConstant _ "[" _ IndexExpression _ "]"
    ArrayConstant   <- ConstantAccess
    StringConstant  <- ConstantAccess

# 6.8.8.3 (complete)
    FieldDesignatedConstant <- RecordConstant _ "." _ FieldSpecifier | ConstantFieldIdentifier
    RecordConstant          <- ConstantAccess

# 6.8.8.4 (complete)
    SubstringConstant   <- StringConstant _ "[" _ IndexExpression _ ".." _ IndexExpression _ "]"

# 6.9.1 (complete)
#    Statement   <- ( Label _ ":" _ )? ( SimpleStatement | StructuredStatement )
# Need a longest match on the label because of the Prospero extension that labels can be identifiers. Alternatively, maintain a list of defined labels that are in scope.
    Statement   <- ( SimpleStatement |  StructuredStatement ) | Label _ ":" _ ( SimpleStatement | StructuredStatement )

# 6.9.2.1 (complete)
    SimpleStatement <- EmptyStatement | AssignmentStatement | ProcedureStatement | GotoStatement
    EmptyStatement  <- eps

# 6.9.2.2 (complete)
    AssignmentStatement <- ( VariableAccess / FunctionIdentifier ) _ ":=" _ Expression

# 6.9.2.3 (complete) #BNV Extended for required procedures.
    ProcedureStatement  <-
                         / READLN _ ReadlnParameterList
                         / READSTR _ ReadstrParameterList
                         / READ _ ReadParameterList
                         / WRITELN _ WritelnParameterList?
                         / WRITESTR _ WritestrParameterList
                         / WRITE _ WriteParameterList
                         / ProcedureName _ ActualParameterList?

# 6.9.2.4 (complete)
    GotoStatement       <- GOTO _ Label

# 6.9.3.1 (complete)
    StructuredStatement <- CompoundStatement / ConditionalStatement / RepetitiveStatement / WithStatement
    StatementSequence   <- Statement ( _ ";" _ Statement )*

# 6.9.3.2 (complete)
    CompoundStatement   <- :BEGIN _ StatementSequence _ :END

# 6.9.3.3 (complete)
    ConditionalStatement    <- IfStatement / CaseStatement

# 6.9.3.4 (complete)
    IfStatement <- IF _ BooleanExpression _ THEN _ Statement ( _ ElsePart )?
    ElsePart    <- ELSE _ Statement

# 6.9.3.5 (complete)
    CaseStatement           <- CASE _ CaseIndex _ OF _ ( CaseListElement ( _ ";" _ CaseListElement )* ( _ ";"? _ CaseStatementCompleter )? | _ CaseStatementCompleter ) _ ";"? _ END
    CaseIndex               <- Expression
    CaseListElement         <- CaseConstantList _ ":" _ Statement
    CaseStatementCompleter  <- OTHERWISE _ StatementSequence

# 6.9.3.6 (complete)
    RepetitiveStatement <- RepeatStatement / WhileStatement / ForStatement

# 6.9.3.7 (complete)
    RepeatStatement <- REPEAT _ StatementSequence _ UNTIL _ BooleanExpression

# 6.9.3.8 (complete)
    WhileStatement  <- WHILE _ BooleanExpression _ DO _ Statement

# 6.9.3.9.1 (complete)
    ForStatement    <- FOR _ ControlVariable _ IterationClause _ DO _ Statement
    ControlVariable <- EntireVariable
    IterationClause <- SequenceIteration / SetMemberIteration

# 6.9.3.9.2 (complete)
    SequenceIteration   <- ":=" _ InitialValue _ ( TO / DOWNTO ) _ FinalValue
    InitialValue        <- Expression
    FinalValue          <- Expression

# 6.9.3.9.3 (complete)
    SetMemberIteration  <- IN _ SetExpression
    SetExpression       <- Expression

# 6.9.3.10 (complete)
    WithStatement                   <- WITH _ WithList _ DO _ Statement
    WithList                        <- WithElement ( _ "," _ WithElement)*
    WithElement                     <- VariableAccess / ConstantAccess
    FieldDesignatorIdentifier       <- Identifier
    ConstantFieldIdentifier         <- Identifier
    SchemaDiscriminantIdentifier    <- Identifier

# 6.9.4 Threats

# 6.10.1 (complete)
    ReadParameterList   <- "(" _ ( FileVariable _ "," _ )? VariableAccess _ ( "," _ VariableAccess _ )* ")"

# 6.10.2 (complete)
    ReadlnParameterList <- ( "(" _ ( FileVariable / VariableAccess ) _ ( "," _ VariableAccess _ )* ")" )?

# 6.10.3 (complete)
    WriteParameterList  <- "(" _ ( FileVariable _ "," _ )? WriteParameter _ ( "," _ WriteParameter _ )* ")"
    WriteParameter      <- Expression ( _ ":" _ Expression ( _ ":" _ Expression )? )?

# 6.10.4 (complete)
    WritelnParameterList    <- ( "(" _ ( FileVariable | WriteParameter ) _ ( "," _ WriteParameter _ )* ")" )?

# 6.11.1 (complete)
    ModuleDeclaration       <- ModuleHeadeing ( _ ";" _ ModuleBlock )? /
                               ModuleIdentification _ ";" _ ModuleBlock
    ModuleHeadeing          <- MODULE Comment? BNVModuleName Comment? InterfaceDirective? Comment? ( "(" ModuleParameterList ")" Comment? )? ";" _ InterfaceSpecificationPart _ ImportPart _ ( ConstantDefinitionPart / TypeDefinitionPart / VariableDeclarationPart / ProcedureAndFunctionHeadingPart)* _ END
    ModuleParameterList     <- IdentifierList
    ProcedureAndFunctionHeadingPart <- ( ProcedureHeading / FunctionHeading ) _ ";"
    ModuleIdentification    <- MODULE Comment? ModuleIdenifier Comment? ImplementationDirective
    ModuleIdenifier         <- Identifier
    ModuleBlock             <- ImportPart _ ( ConstantDefinitionPart / TypeDefinitionPart / VariableDeclarationPart / ProcedureAndFunctionDeclarationPart )* _ InitializationPart? _ FinalizationPart? _ END
    InitializationPart      <- TO _ BEGIN _ DO _ Statement _ ";"
    FinalizationPart        <- TO _ END _ DO _ Statement _ ";"
    BNVModuleName           <- Identifier

# 6.11.2 (complete)
    InterfaceSpecificationPart  <- EXPORT _ ( ExportPart _ ";" )+
    ExportPart                  <- Identifier _ "=" _ "(" _ ExportList _ ")"
    ExportList                  <- ( ExportClause | ExportRange ) ( _ "," _ ( ExportClause | ExportRange ) )*
    ExportClause                <- ExportableName | ExportRenamingClause
    ExportRenamingClause        <- ExportableName _ "=>" _ Identifier
    ExportableName              <- ConstantName / TypeName / SchemaName / ( ( PROTECTED _ )? VariableName ) / ProcedureName / FunctionName
    ExportRange                 <- FirstConstantName _ ".." _ LastConstantName
    FirstConstantName           <- ConstantName
    LastConstantName            <- ConstantName
    ConstituentIdentifier       <- Identifier
    InterfaceIdentifier         <- Identifier

# 6.11.3 (complete)
    ImportSpecification         <- InterfaceIdentifier ( _ AccessQualifier )? _ ImportQualifier?
    AccessQualifier             <- QUALIFIED
    ImportQualifier             <- ( SelectiveImportOption _ )? "(" _ ImportList _ ")"
    SelectiveImportOption       <- ONLY
    ImportList                  <- ImportClause _ ("," _ ImportClause _)*
    ImportClause                <- ConstituentIdentifier | ImportRenamingClause
    ImportRenamingClause        <- ConstituentIdentifier _ "=>" _ Identifier
    ImportedInterfaceIdentifier <- Identifier

# 6.11.4 Required interfaces TODO

# 6.12 (complete)
    MainProgramDeclaration  <- ProgramHeading _ ";" :Spacing? MainProgramBlock # BNV Discarding newlines that have no correspondence in D.
    ProgramHeading          <- PROGRAM Comment? BNVProgramName ( Comment? "(" _ ProgramParameterList _ ")" )?
    ProgramParameterList    <- IdentifierList
    MainProgramBlock        <- _ Block
    # BNV extensions
    BNVProgramName          <- Identifier

# 6.13
    Program             <- _ ProgramBlock _
    ProgramBlock        <- ( ProgramComponent _ )+
    ProgramComponent    <- ( MainProgramDeclaration _ "." ) / ( ModuleDeclaration _ "." )

# Keywords 6.1.2
    AND         <- "and"i
    AND_THEN    <- "and_then"i
    ARRAY       <- "array"i
    BEGIN       <- "begin"i
    BINDABLE    <- "bindable"i
    CASE        <- "case"i
    CONST       <- "const"i
    DIV         <- "div"i
    DO          <- "do"i
    DOWNTO      <- "downto"i
    ELSE        <- "else"i
    END         <- "end"i
    EXPORT      <- "export"i
    FILE        <- "file"i
    FOR         <- "for"i
    FUNCTION    <- "function"i
    GOTO        <- "goto"i
    IF          <- "if"i
    IMPORT      <- "import"i
    IN          <- "in"i
    LABEL       <- "label"i
    MOD         <- "mod"i
    MODULE      <- "module"i
    NIL         <- "nil"i
    NOT         <- "not"i
    OF          <- "of"i
    ONLY        <- "only"i
    OR          <- "or"i
    OR_ELSE     <- "or_else"i
    OTHERWISE   <- "otherwise"i
    PACKED      <- "packed"i
    POW         <- "pow"i
    PROCEDURE   <- "procedure"i
    PROGRAM     <- "program"i
    PROTECTED   <- "protected"i
    QUALIFIED   <- "qualified"i
    RECORD      <- "record"i
    REPEAT      <- "repeat"i
    RESTRICTED  <- "restricted"i
    SET         <- "set"i
    THEN        <- "then"i
    TO          <- "to"i
    TYPE        <- "type"i
    UNTIL       <- "until"i
    VALUE       <- "value"i
    VAR         <- "var"i
    WHILE       <- "while"i
    WITH        <- "with"i

# Separators
    COMMA       <- ","
    DOT         <- "."

# Built-ins
    READ        <- "read"i
    READLN      <- "readln"i
    READSTR     <- "readstr"i
    WRITE       <- "write"i
    WRITELN     <- "writeln"i
    WRITESTR    <- "writestr"i
`;
